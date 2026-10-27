#!/usr/bin/env bash
# Generates the Flutter scaffold and overlays this repo's files on top of it.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
flutter create --org com.example --project-name sim_data_app --platforms android "$TMP/sim_data_app"
cp -r "$SRC/lib" "$SRC/assets" "$SRC/pubspec.yaml" "$TMP/sim_data_app/"
cp -r "$SRC/android/app/src/main/." "$TMP/sim_data_app/android/app/src/main/"
cd "$TMP/sim_data_app" && flutter pub get && dart run flutter_launcher_icons
cd "$SRC"
echo "Done: $TMP/sim_data_app"
echo "Remember: set minSdk = 29 in android/app/build.gradle(.kts), then: flutter pub get && flutter run"
