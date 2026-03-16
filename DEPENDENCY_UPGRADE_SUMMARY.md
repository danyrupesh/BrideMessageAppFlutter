## Dependency audit & upgrades

**Scope**: `E:/Freelance/BrideMessageApp/AppFlutter`

### 1. Direct dependencies from your list

All of the key libraries you highlighted are actively used in the app and are **kept**:

- `app_links`: used in `core/navigation/app_links_handler.dart` and wired via `main.dart` for deep links on Android, iOS, Windows, macOS.
- `file_picker`: used in `features/songs/widgets/song_import_sheet.dart` and `features/onboarding/onboarding_screen.dart` for ZIP/database import on all platforms.
- `flutter_riverpod`: core state management across many screens (`search_provider.dart`, `reader_provider.dart`, `sermon_flow_provider.dart`, song/onboarding providers, theme provider, etc.).
- `flutter_widget_from_html`: used in `features/sermons/widgets/sermon_html_preview.dart` for sermon HTML previews.
- `pdf` / `printing`: used in `features/reader/reader_screen.dart`, `features/sermons/sermon_reader_screen.dart`, and `features/songs/song_detail_screen.dart` for Bible/sermon/song PDF generation & printing on mobile + desktop.
- `package_info_plus`: used in `features/settings/settings_screen.dart` and `features/settings/screens/developer_details_screen.dart` for App Info / About screens.
- `sqlite3` / `sqflite` / `sqflite_common_ffi`: used in `core/database/database_manager.dart`, `core/database/fts_search_sqlite3.dart`, and repositories for cross‑platform DB access (Android/iOS via `sqflite`, desktop via FFI + `sqlite3`).

No direct dependency from your list was completely unused, so **nothing was removed** – only upgraded.

Transitive libraries like `_fe_analyzer_shared`, `analyzer`, `test*`, `wakelock_plus`, `webview_flutter*`, `win32*`, `image`, `just_audio`, `fwfh_*` stay managed by their parent packages.

### 2. Version upgrades applied (pubspec.yaml)

The following direct dependencies were safely bumped to newer versions, and `flutter pub get` completed successfully:

- `app_links`: **6.3.2 → 7.0.0**
- `file_picker`: **8.1.6 → 10.3.10**
- `flutter_riverpod`: **3.2.1 → 3.3.1**
- `flutter_widget_from_html`: **0.14.11 → 0.17.1**
- `pdf`: **3.11.3 → 3.12.0**
- `printing`: **5.14.2 → 5.14.3**
- `package_info_plus`: **8.0.2 → 9.0.0**
- `sqlite3`: **3.1.0 → 3.2.0**

These changes are reflected in:

- `pubspec.yaml` (updated constraints)
- `pubspec.lock` (resolved versions, including updated `fwfh_*`, `just_audio`, `wakelock_plus`, and `webview_flutter*` transitive dependencies)

### 3. Feature coverage by platform (after upgrades)

- **Deep links & custom protocols (mobile + desktop)**  
  - `app_links 7.0.0` continues to drive the `appLinksHandlerProvider` in `core/navigation/app_links_handler.dart`, which is read in `main.dart` (`BrideMessageApp`) and integrates with `protocol_handler` + `windows_single_instance` on Windows.  
  - This keeps link flows working across Android, iOS, macOS, and Windows (where supported by each plugin).

- **File import/export & database onboarding (mobile + desktop)**  
  - `file_picker 10.3.10` is used in `SongImportSheet` and `OnboardingScreen` for ZIP imports. The usage pattern (`FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: false)`) is still supported in 10.x, covering Android, iOS, and desktop platforms.
  - `file_selector` + `path_provider` remain available for desktop file saving (e.g. PDFs and text exports).

- **Local databases (Android, iOS, Windows, macOS)**  
  - `sqflite` (mobile) + `sqflite_common_ffi` + `sqlite3 3.2.0` (desktop) continue to work together via `DatabaseManager` and the various repositories, with no API changes required by this minor bump.
  - FTS/diagnostics remain wired through `DatabaseManager.logSqliteDiagnostics()` in `main.dart`, unchanged by the upgrade.

- **HTML/media rendering (all platforms)**  
  - `flutter_widget_from_html 0.17.1` plus updated transitive add‑ons (`flutter_widget_from_html_core`, `fwfh_*`, `webview_flutter*`, `just_audio`, `wakelock_plus`) continue to power `SermonHtmlPreview` and any HTML/media content; no breaking API changes affected the current usage pattern (`HtmlWidget(html, ...)`).

- **PDF generation & printing (all platforms)**  
  - Bible, sermon, and hymn PDFs still render via `pdf 3.12.0` and print/download via `printing 5.14.3` in `ReaderScreen`, `SermonReaderScreen`, and `SongDetailScreen`.  
  - Desktop save‑dialogs and mobile document-directory flows (via `DesktopFileSaver`, `path_provider`, `open_filex`) are unchanged.

- **App info / About screens (all platforms)**  
  - `package_info_plus 9.0.0` is still used through `PackageInfo.fromPlatform()` in `SettingsScreen` and `DeveloperDetailsScreen`; the API used there remains valid in 9.x.

### 4. Notes and next steps

- **Unused libraries**: None of the highlighted direct dependencies were unused; all are tied to real features (deep links, import/export, HTML rendering, PDFs, app info, database access).  
- **Transitive-only packages**: Libraries like `_fe_analyzer_shared`, `analyzer`, `test_*`, `wakelock_plus`, `webview_flutter*`, `win32*`, `image`, `just_audio`, `fwfh_*` are kept as‑is and will evolve automatically when their parent packages are updated in the future.
- **Further optimization (optional)**:  
  - Run `flutter pub outdated` occasionally to assess future upgrades.  
  - If you later decide to simplify HTML/media capabilities, we could consider trimming some `fwfh_*` features (e.g. video or audio) to reduce binary size, but that would be a functional trade‑off and is not applied here.

