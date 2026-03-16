import 'package:unorm_dart/unorm_dart.dart';

/// Normalizes Tamil (and other Unicode) text to NFC to improve shaping/search.
String normalizeTamil(String input) {
  if (input.isEmpty) return input;
  return nfc(input);
}

/// Convenience helper to normalize a list of paragraph strings.
List<String> normalizeParagraphs(List<String> paragraphs) {
  return paragraphs.map(normalizeTamil).toList(growable: false);
}
