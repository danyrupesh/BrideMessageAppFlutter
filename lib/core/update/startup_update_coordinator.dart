import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart' hide AppUpdateInfo;
import 'package:url_launcher/url_launcher.dart';

import '../navigation/app_router.dart';
import 'app_restart_helper.dart';
import 'update_service.dart';

class StartupUpdateCoordinator extends StatefulWidget {
  final Widget child;

  const StartupUpdateCoordinator({super.key, required this.child});

  @override
  State<StartupUpdateCoordinator> createState() =>
      _StartupUpdateCoordinatorState();
}

class _StartupUpdateCoordinatorState extends State<StartupUpdateCoordinator> {
  final UpdateService _updateService = UpdateService();
  bool _running = false;

  BuildContext? get _dialogContext => appRootNavigatorKey.currentContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupChecks();
    });
  }

  Future<void> _runStartupChecks() async {
    if (_running || !mounted) return;
    _running = true;

    try {
      final appUpdate = await _updateService.checkAppUpdate();
      if (!mounted) return;

      if (appUpdate != null) {
        final appDone = await _handleAppUpdate(appUpdate);
        if (!appDone && appUpdate.mandatory) {
          return;
        }
      }

      final dbUpdates = await _updateService.checkDatabaseUpdates();
      if (!mounted || dbUpdates.isEmpty) return;

      final mandatoryUpdates = dbUpdates
          .where((update) => update.mandatory)
          .toList();
      final optionalUpdates = dbUpdates
          .where((update) => !update.mandatory)
          .toList();

      if (mandatoryUpdates.isNotEmpty) {
        await _runDatabaseUpdateFlow(mandatoryUpdates, mandatory: true);
      }

      if (!mounted || optionalUpdates.isEmpty) return;
      await _runDatabaseUpdateFlow(optionalUpdates, mandatory: false);
    } finally {
      _running = false;
    }
  }

  Future<bool> _handleAppUpdate(AppUpdateInfo info) async {
    if (Platform.isAndroid) {
      return _handleAndroidAppUpdate(info);
    }

    return _showDesktopAppUpdateDialog(info);
  }

  Future<bool> _handleAndroidAppUpdate(AppUpdateInfo info) async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return true;
      }

      if (info.mandatory) {
        await InAppUpdate.performImmediateUpdate();
      } else {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
      return true;
    } catch (e) {
      if (!info.mandatory) return false;
      final dialogContext = _dialogContext;
      if (!mounted || dialogContext == null) return false;
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Update Required'),
            content: Text(
              'Could not start Google Play update flow. Please update the app from Play Store.\n\n$e',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final uri = Uri.parse(info.url);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Open Play Store'),
              ),
            ],
          );
        },
      );
      return false;
    }
  }

  Future<bool> _showDesktopAppUpdateDialog(AppUpdateInfo info) async {
    bool launched = false;
    final dialogContext = _dialogContext;
    if (dialogContext == null) {
      return !info.mandatory;
    }

    final isZip = info.packageType == 'zip';
    final updateHint = isZip
        ? 'The update is a ZIP package. Extract and replace the full app folder (not only .exe).'
        : 'Run the downloaded installer package to complete the update.';

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: !info.mandatory,
      builder: (context) {
        return PopScope(
          canPop: !info.mandatory,
          child: AlertDialog(
            title: Text(
              info.mandatory ? 'Update Required' : 'Update Available',
            ),
            content: Text(
              'Current: ${info.currentVersion}\nLatest: ${info.targetVersion}\n\n'
              'A new app version is available.\n\n$updateHint',
            ),
            actions: [
              if (!info.mandatory)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
              if (info.mandatory)
                TextButton(onPressed: _exitApp, child: const Text('Exit App')),
              FilledButton(
                onPressed: () async {
                  final uri = Uri.parse(info.url);
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  launched = ok;
                  if (ok && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Update Now'),
              ),
            ],
          ),
        );
      },
    );

    return launched || !info.mandatory;
  }

  Future<void> _runDatabaseUpdateFlow(
    List<DatabaseUpdateInfo> updates, {
    required bool mandatory,
  }) async {
    if (updates.isEmpty || !mounted) return;

    final dialogContext = _dialogContext;
    if (dialogContext == null) return;

    final names = updates.map((e) => e.displayName).join(', ');
    if (!mandatory) {
      final details = updates
          .map((e) {
            final message = (e.updateMessage ?? '').trim();
            final fallback = 'New database version v${e.version} is available.';
            return '${e.displayName} (v${e.version})\n${message.isEmpty ? fallback : message}';
          })
          .join('\n\n');
      final shouldUpdate =
          await showDialog<bool>(
            context: dialogContext,
            builder: (context) {
              return AlertDialog(
                title: const Text('Database Update Available'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Text('Updates found for: $names\n\n$details'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Update Now'),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!shouldUpdate || !mounted) return;
    }

    final status = ValueNotifier<String>('Preparing updates...');
    final cancelToken = CancelToken();
    var cancelledByUser = false;
    var progressDialogOpen = true;

    if (mounted) {
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(
                mandatory ? 'Database Update Required' : 'Updating Database',
              ),
              content: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, value, __) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(value),
                    ],
                  );
                },
              ),
              actions: [
                if (!mandatory)
                  TextButton(
                    onPressed: () {
                      cancelledByUser = true;
                      progressDialogOpen = false;
                      cancelToken.cancel('Cancelled by user');
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          );
        },
      );
    }

    try {
      await _updateService.applyDatabaseUpdates(
        updates,
        onStatus: (message) => status.value = message,
        cancelToken: cancelToken,
      );
      if (mounted && progressDialogOpen) {
        appRootNavigatorKey.currentState?.pop();
      }
      if (mounted) {
        await AppRestartHelper.restartAfterDatabaseUpgrade();
        return;
      }
    } catch (e) {
      if (cancelledByUser ||
          (e is DioException && e.type == DioExceptionType.cancel)) {
        return;
      }

      if (mounted) {
        if (progressDialogOpen) {
          appRootNavigatorKey.currentState?.pop();
        }
        await showDialog<void>(
          context: dialogContext,
          barrierDismissible: !mandatory,
          builder: (context) {
            return PopScope(
              canPop: !mandatory,
              child: AlertDialog(
                title: Text(
                  mandatory ? 'Database Update Failed' : 'Update Failed',
                ),
                content: Text(
                  mandatory
                      ? 'A required database update could not be applied. Please retry.\n\n$e'
                      : 'Could not apply database update.\n\n$e',
                ),
                actions: [
                  if (!mandatory)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  if (mandatory)
                    TextButton(
                      onPressed: _exitApp,
                      child: const Text('Exit App'),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          },
        );
      }

      if (mandatory && mounted) {
        await _runDatabaseUpdateFlow(updates, mandatory: true);
      }
    } finally {
      status.dispose();
    }
  }

  void _exitApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      return;
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
