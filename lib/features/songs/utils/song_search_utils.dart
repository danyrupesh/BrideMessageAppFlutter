import 'dart:math';

String buildSongSearchSubtitle({
  required String firstLine,
  required String lyrics,
  required String query,
}) {
  final cleaned = query.trim();
  if (cleaned.isEmpty) return firstLine;

  final lowerQuery = cleaned.toLowerCase();
  final firstLineClean = firstLine.replaceAll('\n', ' ').trim();
  if (firstLineClean.toLowerCase().contains(lowerQuery)) {
    return firstLineClean;
  }

  final lyricsClean = lyrics.replaceAll('\n', ' ').trim();
  final lyricsLower = lyricsClean.toLowerCase();
  final idx = lyricsLower.indexOf(lowerQuery);
  if (idx < 0) return firstLineClean;

  const contextChars = 20;
  final start = max(0, idx - contextChars);
  final end = min(lyricsClean.length, idx + lowerQuery.length + contextChars);
  var snippet = lyricsClean.substring(start, end).trim();

  if (start > 0) snippet = '...$snippet';
  if (end < lyricsClean.length) snippet = '$snippet...';

  return snippet.replaceAll(RegExp(r'\\s+'), ' ');
}
