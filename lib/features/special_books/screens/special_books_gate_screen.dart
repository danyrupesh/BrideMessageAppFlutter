import 'package:flutter/material.dart';

import '../../../core/database/special_books_catalog_repository.dart';
import '../services/special_books_catalog_installer.dart';
import 'special_books_screen.dart';

class SpecialBooksGateScreen extends StatefulWidget {
  const SpecialBooksGateScreen({super.key, required this.lang});

  final String lang;

  @override
  State<SpecialBooksGateScreen> createState() => _SpecialBooksGateScreenState();
}

class _SpecialBooksGateScreenState extends State<SpecialBooksGateScreen> {
  bool _checked = false;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final installed = await SpecialBooksCatalogRepository(
        lang: widget.lang,
      ).isAvailable;
      if (!mounted) return;
      if (installed) {
        setState(() {
          _checked = true;
          _installed = true;
        });
        return;
      }

      final result = await _showImportSheet();
      if (!mounted) return;
      if (result == true) {
        setState(() {
          _checked = true;
          _installed = true;
        });
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  Future<bool?> _showImportSheet() {
    final installer = SpecialBooksCatalogInstaller();
    final isTamil = widget.lang == 'ta';

    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isTamil
                      ? 'சிறப்பு புத்தகங்கள் பதிவிறக்கம் / இறக்குமதி'
                      : 'Special Books Download / Import',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isTamil
                      ? 'தொடர முன் Tamil Special Books Catalog நிறுவ வேண்டும்.'
                      : 'Install Special Books catalog before continuing.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await installer.installByDownload(widget.lang);
                    if (!context.mounted) return;
                    Navigator.of(context).pop(ok);
                  },
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(isTamil ? 'பதிவிறக்கம்' : 'Download'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final ok = await installer.installByFilePicker(widget.lang);
                    if (!context.mounted) return;
                    Navigator.of(context).pop(ok);
                  },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(isTamil ? 'இறக்குமதி' : 'Import'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_installed) {
      return SpecialBooksScreen(lang: widget.lang);
    }

    return const Scaffold(body: SizedBox.shrink());
  }
}

