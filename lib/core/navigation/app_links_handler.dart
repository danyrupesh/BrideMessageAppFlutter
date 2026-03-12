import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_router.dart';

final appLinksProvider = Provider<AppLinks>((ref) => AppLinks());

class AppLinksHandler {
  final Ref ref;
  late StreamSubscription<Uri> _sub;

  AppLinksHandler(this.ref) {
    _init();
  }

  void _init() {
    final appLinks = ref.read(appLinksProvider);

    // Handle links when the app is already running
    _sub = appLinks.uriLinkStream.listen((uri) {
      debugPrint('Incoming deep link (running): $uri');
      _handleLink(uri);
    });

    // Handle links that opened the app
    appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('Incoming deep link (initial): $uri');
        _handleLink(uri);
      }
    });
  }

  void _handleLink(Uri uri) {
    final router = ref.read(appRouterProvider);
    
    // 1) https://endtimebride.in/appshare/sermon?id=... -> path is /appshare/sermon
    // 2) bridemessage://appshare/sermon?id=... -> authority is appshare, path is /sermon
    
    String fullPath = uri.path;
    
    if (uri.authority == 'appshare') {
       fullPath = '/appshare${uri.path}';
       // Clean up any double slashes just in case
       fullPath = fullPath.replaceAll('//', '/');
    } else if (!fullPath.startsWith('/')) {
       fullPath = '/$fullPath';
    }
    
    if (fullPath.startsWith('/appshare')) {
      final finalRoute = fullPath + (uri.hasQuery ? '?${uri.query}' : '');
      debugPrint('Routing deep link to: $finalRoute');
      router.push(finalRoute);
    }
  }

  /// Exposed for manual injection from WindowsSingleInstance
  void processUriDirectly(Uri uri) {
    debugPrint('Incoming deep link (manual): $uri');
    _handleLink(uri);
  }

  void dispose() {
    _sub.cancel();
  }
}

// Global provider to initialize the handler
final appLinksHandlerProvider = Provider<AppLinksHandler>((ref) {
  final handler = AppLinksHandler(ref);
  ref.onDispose(() => handler.dispose());
  return handler;
});
