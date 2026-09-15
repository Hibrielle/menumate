#!/bin/zsh
# Materialize the example as a disposable, independently cloneable local Git repo.
set -euo pipefail
repository="${0:A:h:h}"
base="${1:-$repository/build/local-packs}"
mkdir -p "$base"
staging=$(mktemp -d "$base/image-tools-XXXXXXXX")
pack="$staging/image-tools-pack"
mkdir -p "$pack"
cp -R "$repository/examples/image-tools-pack/." "$pack/"
git -C "$pack" init -q -b main
git -C "$pack" add .
git -C "$pack" -c user.name='MenuMate Example' -c user.email='example@menumate.local' -c commit.gpgsign=false commit -qm 'Local image tools example'
print -r -- "$pack"
