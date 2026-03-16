import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/models/hymn_models.dart';
import '../providers/search_provider.dart';
import '../../common/widgets/cards.dart';

class SongResultsTab extends ConsumerWidget {
  const SongResultsTab({super.key});

  String _buildSearchSubtitle(Hymn hymn, String query) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return hymn.firstLine;

    final lowerQuery = cleaned.toLowerCase();
    final firstLine = hymn.firstLine.replaceAll('\n', ' ').trim();
    if (firstLine.toLowerCase().contains(lowerQuery)) {
      return firstLine;
    }

    final lyrics = hymn.lyrics.replaceAll('\n', ' ').trim();
    final lyricsLower = lyrics.toLowerCase();
    final idx = lyricsLower.indexOf(lowerQuery);
    if (idx < 0) return firstLine;

    const contextChars = 20;
    final start = max(0, idx - contextChars);
    final end = min(lyrics.length, idx + lowerQuery.length + contextChars);
    var snippet = lyrics.substring(start, end).trim();

    if (start > 0) snippet = '…$snippet';
    if (end < lyrics.length) snippet = '$snippet…';

    return snippet.replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Text(
          'Error: ${state.error}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (state.query.isEmpty || state.query.length <= 2) {
      return const Center(child: Text('Type at least 3 characters to search'));
    }
    final results = state.songResults;
    if (results.isEmpty) {
      return Center(child: Text('No songs found for "${state.query}"'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hymn = results[index];
        return SongListCard(
          number: hymn.hymnNo,
          title: hymn.title,
          subtitle: _buildSearchSubtitle(hymn, state.query),
          keyBadge: hymn.chord.isEmpty ? null : hymn.chord,
          isFavorite: hymn.isFavorite,
          highlightQuery: state.query,
          onTap: () {
            context.push(
              '/song-detail',
              extra: hymn.hymnNo,
            );
          },
          onToggleFavorite: null,
        );
      },
    );
  }
}
