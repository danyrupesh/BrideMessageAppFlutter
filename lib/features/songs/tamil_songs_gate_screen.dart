import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/tamil_hymns_importer.dart';
import 'widgets/tamil_song_import_sheet.dart';
import 'tamil_songs_screen.dart';

class TamilSongsGateScreen extends ConsumerStatefulWidget {
  const TamilSongsGateScreen({super.key});

  @override
  ConsumerState<TamilSongsGateScreen> createState() => _TamilSongsGateScreenState();
}

class _TamilSongsGateScreenState extends ConsumerState<TamilSongsGateScreen> {
  bool _checked = false;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final installed = await TamilHymnsImporter.isInstalled();
      if (!mounted) return;
      if (installed) {
        setState(() {
          _checked = true;
          _installed = true;
        });
      } else {
        final result = await TamilSongImportSheet.show(context);
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
      return const TamilSongsScreen();
    }

    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}
