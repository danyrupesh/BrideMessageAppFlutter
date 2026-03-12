import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/hymns_importer.dart';
import 'widgets/song_import_sheet.dart';
import 'songs_screen.dart';

class SongsGateScreen extends ConsumerStatefulWidget {
  const SongsGateScreen({super.key});

  @override
  ConsumerState<SongsGateScreen> createState() => _SongsGateScreenState();
}

class _SongsGateScreenState extends ConsumerState<SongsGateScreen> {
  bool _checked = false;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final installed = await HymnsImporter.isInstalled();
      if (!mounted) return;
      if (installed) {
        setState(() {
          _checked = true;
          _installed = true;
        });
      } else {
        final result = await SongImportSheet.show(context);
        if (!mounted) return;
        if (result == true) {
          setState(() {
            _checked = true;
            _installed = true;
          });
        } else {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_installed) {
      return const SongsScreen();
    }

    // Fallback; in practice we either popped or marked installed.
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}

