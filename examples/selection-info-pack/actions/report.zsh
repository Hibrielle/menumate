#!/bin/zsh
emulate -L zsh
set -euo pipefail
(( $# > 0 )) || { print -u2 -- 'Select at least one file'; exit 2; }
mode=$(print -rn -- "${MENUMATE_INPUT:-}" | /usr/bin/plutil -extract mode raw -expect string -o - - 2>/dev/null) || {
  print -u2 -- 'Expected a JSON object with a string mode'; exit 2
}
[[ "$mode" == names || "$mode" == paths ]] || {
  print -u2 -- 'mode must be names or paths'; exit 2
}
for item in "$@"; do
  if [[ "$mode" == names ]]; then print -r -- "${item:t}"
  else print -r -- "$item"
  fi
done
