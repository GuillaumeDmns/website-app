#!/usr/bin/env bash
# The release notes users read, in French: Google Play's "What's new" (fr-FR) and the top of the GitHub release.
# They are the message of the annotated tag, written for users, not developers:
#   git tag -a v0.17.0 -m "• Raccourcis Domicile et Travail en appui long sur l'icône
#   • Notifications de trajet plus claires"
# A tag without a message (lightweight), or no tag at all (dry run), gets a generic line.
# Google Play takes 500 characters at most: longer notes fail here, before anything is published.
#   tool/release-notes.sh v0.17.0
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C.UTF-8

tag=${1:-}
notes=""
if [ -n "$tag" ] && [ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" = tag ]; then
  # Without a signed tag's signature, trailing spaces and blank lines around
  notes=$(git tag -l --format='%(contents)' "$tag" |
    sed -e '/^-----BEGIN /,$d' -e 's/[[:space:]]*$//' |
    awk 'NF { started = 1; for (; blank > 0; blank--) print ""; print; next } started { blank++ }')
fi
if [ -z "$notes" ]; then
  notes="Corrections et améliorations."
fi

length=$(printf '%s' "$notes" | wc -m)
if (( length > 500 )); then
  echo "Release notes of $tag: $length characters, Google Play takes 500 at most (git tag -f -a $tag to rewrite them)" >&2
  exit 1
fi
printf '%s\n' "$notes"
