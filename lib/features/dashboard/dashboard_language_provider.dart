import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardLanguageNotifier extends Notifier<String> {
  @override
  String build() => 'en';

  void setLang(String lang) => state = lang;
}

final dashboardLanguageProvider = NotifierProvider<DashboardLanguageNotifier, String>(
  DashboardLanguageNotifier.new,
);
