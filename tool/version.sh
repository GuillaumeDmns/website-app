#!/usr/bin/env bash
# The app's version from git, the only place it is kept: the last tag vX.Y.Z of the commit's history.
# Prints "<name> <build number> <commit>":
#   on the tag itself:          0.4.0     40000   1a2b3c4
#   12 commits after it:        0.4.0-12  40012   5d6e7f8
#   with uncommitted changes:   0.4.0-12  40012   5d6e7f8-dirty
# The build number (Android versionCode) grows with the version, then with the commits after the tag (99 at most):
# a newer build always installs over an older one, and a tag's build is higher than every build before it.
set -euo pipefail
cd "$(dirname "$0")/.."

describe=$(git describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' --long --dirty 2>/dev/null) ||
  describe="v0.0.0-$(git rev-list --count HEAD)-g$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo -dirty)"

dirty=""
if [[ $describe == *-dirty ]]; then
  dirty="-dirty"
  describe=${describe%-dirty}
fi
commit=${describe##*-g}          # v0.4.0-12-g5d6e7f8 → 5d6e7f8
rest=${describe%-g*}             # v0.4.0-12
ahead=${rest##*-}                # 12
version=${rest%-*}               # v0.4.0
version=${version#v}             # 0.4.0
IFS=. read -r major minor patch <<<"$version"

if (( minor > 99 || patch > 99 )); then
  echo "Version $version: minor and patch go up to 99, or the build number would no longer grow with the version" >&2
  exit 1
fi
code=$(( (major * 10000 + minor * 100 + patch) * 100 + (ahead > 99 ? 99 : ahead) ))
name=$version
if (( ahead > 0 )); then
  name="$version-$ahead"
fi
echo "$name $code $commit$dirty"
