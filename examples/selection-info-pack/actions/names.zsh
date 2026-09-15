#!/bin/zsh
emulate -L zsh
set -euo pipefail
(( $# > 0 )) || { print -u2 -- 'Select at least one file'; exit 2; }
for item in "$@"; do
  print -r -- "${item:t}"
done
