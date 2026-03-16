import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

class AppPdfFonts {
  static Future<pw.Font> tamilSerifRegular() {
    return _load('NotoSerifTamil-Regular.ttf');
  }

  static Future<pw.Font> tamilSerifBold() {
    return _load('NotoSerifTamil-Bold.ttf');
  }

  // Backwards-compat for existing callers.
  static Future<pw.Font> tamilRegular() => tamilSerifRegular();
  static Future<pw.Font> tamilBold() => tamilSerifBold();

  static Future<pw.Font> _load(String filename) async {
    final data = await rootBundle.load('assets/fonts/$filename');
    return pw.Font.ttf(data);
  }
}

