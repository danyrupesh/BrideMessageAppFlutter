import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_discovery_service.dart';

/// Provides the singleton DatabaseDiscoveryService instance
final databaseDiscoveryProvider =
    Provider((ref) => DatabaseDiscoveryService());

/// Fetches available databases from the server
/// Usage: ref.watch(availableDatabasesProvider(apiBaseUrl))
final availableDatabasesProvider =
    FutureProvider.family<List<DatabaseInfo>, String>((ref, apiBaseUrl) async {
  final service = ref.watch(databaseDiscoveryProvider);
  return await service.availableDatabases(apiBaseUrl);
});

/// Fetches info for a specific database
/// Usage: ref.watch(specificDatabaseProvider((apiBaseUrl, databaseId)))
final specificDatabaseProvider = FutureProvider.family<DatabaseInfo, 
    ({String apiBaseUrl, String databaseId})>((ref, params) async {
  final service = ref.watch(databaseDiscoveryProvider);
  return await service.databaseInfo(params.apiBaseUrl, params.databaseId);
});

/// Cached reference to the full-bundle database (bridemessage_db_en-ta)
/// This is the default onboarding bundle containing all databases
final fullBundleDatabaseProvider =
    FutureProvider.family<DatabaseInfo, String>((ref, apiBaseUrl) async {
  final service = ref.watch(databaseDiscoveryProvider);
  return await service.databaseInfo(apiBaseUrl, 'bridemessage_db_en-ta');
});
