import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reading_state_repository.dart';
import '../models/reading_flow_models.dart';

final readingStateRepositoryProvider = Provider<ReadingStateRepository>(
  (_) => ReadingStateRepository(),
);

final recentReadsProvider = FutureProvider<List<RecentReadItem>>((ref) async {
  final repo = ref.read(readingStateRepositoryProvider);
  return repo.listRecentReads(limit: 10);
});
