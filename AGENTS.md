# Repository Guidelines

## Project Structure & Module Organization

EasyPlay is a Flutter board-game app for Android and Web. Application code lives in `lib/`: `main.dart` starts the app, `game_page.dart` coordinates play, `board.dart` draws the board, and `game_session.dart` owns game state and rules. Game entry points are in `lib/games/`; LAN code is in `lib/lan/`. Keep rules and storage logic out of widgets. Tests live in `test/` and generally mirror the feature they cover. Platform shells are in `android/` and `web/`; bundled KataGo models, configuration, and licenses are in `assets/katago/`. See `docs/DEVELOPMENT.md` for detailed behavior and build notes.

## Build, Test, and Development Commands

- `flutter pub get`: install dependencies from `pubspec.yaml`.
- `flutter run -d chrome`: run the Web app with hot reload.
- `flutter build web`: produce a static Web build in `build/web/`.
- `python3 tools/serve_web.py --port 8080`: preview that build with the headers needed by Web KataGo.
- `python3 tools/package_lan_android.py --debug`: bundle Web assets and build the LAN-capable Android APK.
- `flutter test`: run the Flutter test suite.
- `dart analyze lib test`: check Dart code against `analysis_options.yaml`.

## Coding Style & Naming Conventions

Use Dart's standard two-space indentation and run `dart format lib test` before submitting code. Follow the `flutter_lints` rules configured in `analysis_options.yaml`. Name files in `snake_case.dart`, types in `UpperCamelCase`, and variables and methods in `lowerCamelCase`. Keep platform-specific implementations behind the existing native, Web, and stub files rather than adding platform checks throughout UI code.

## Testing Guidelines

Use `flutter_test`; name test files `*_test.dart`. Add a rule test for each new or changed game rule and a widget test when changing navigation or core controls. Run `flutter test` and `dart analyze lib test` for Dart changes. Also run `flutter build web` for layout, asset, or Web changes, and `python3 tools/package_lan_android.py --debug` for Android or LAN changes. No numeric coverage threshold is specified.

## Commit & Pull Request Guidelines

Recent commits use scoped Conventional Commit subjects such as `feat(go): ...`, `fix(engine): ...`, and `test(board): ...`. Keep each commit to one verifiable topic. In a pull request, describe the user-visible change, affected modules, rule variants or remaining gaps, data storage changes, commands run and their results, and known issues. Link a relevant issue when one exists; include screenshots for UI changes.
