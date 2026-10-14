#!/usr/bin/env bash
# flutter build with the version of git (tool/version.sh) for Android, the web app and the screen "À propos":
#   tool/build.sh apk --flavor prod
#   tool/build.sh web --dart-define=APP_ENV=prod --no-web-resources-cdn
# A plain "flutter build" works too, as a version 0.0.0 build ("version de développement" in the app).
set -euo pipefail
cd "$(dirname "$0")/.."

read -r name code commit < <(tool/version.sh)
echo "Version $name (build $code, commit $commit)"
exec flutter build "$@" --build-name="$name" --build-number="$code" \
  --dart-define=APP_VERSION="$name" --dart-define=APP_BUILD="$code" --dart-define=APP_COMMIT="$commit"
