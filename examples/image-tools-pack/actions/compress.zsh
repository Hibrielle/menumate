#!/bin/zsh
emulate -L zsh
set -euo pipefail
quality=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract quality raw -o - -)
edge=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract maxEdge raw -o - -)
output=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract output raw -o - -)
[[ "$quality" == <-> && "$quality" -ge 10 && "$quality" -le 100 ]] || { print -u2 'Invalid JPEG quality'; exit 2; }
[[ "$edge" == <-> && "$edge" -le 20000 ]] || { print -u2 'Invalid image size'; exit 2; }
[[ "$output" == same || "$output" == subfolder ]] || { print -u2 'Invalid output location'; exit 2; }
resultSuffix="compressed"
resultFolder="Compressed Images"
if [[ "${MENUMATE_LOCALE:-en}" == zh* ]]; then
  resultSuffix="压缩"
  resultFolder="压缩图片"
fi
for source in "$@"; do
  [[ -f "$source" ]] || { print -u2 "Missing input: $source"; exit 2; }
  format=$(/usr/bin/sips -g format "$source" | /usr/bin/awk '/format:/{print $2}')
  [[ "$format" == jpeg ]] || { print -u2 "Not a JPEG image: $source"; exit 2; }
  folder="${source:h}"
  [[ "$output" == subfolder ]] && folder="$folder/$resultFolder"
  /bin/mkdir -p "$folder"
  temporary=$(/usr/bin/mktemp -d "$folder/.menumate-XXXXXXXX")
  trap '/bin/rm -rf -- "$temporary"' EXIT
  convertArgs=(-s format jpeg -s formatOptions "$quality")
  if (( edge > 0 )); then
    longest=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$source" | /usr/bin/awk '/pixelWidth:|pixelHeight:/{if($2>m)m=$2}END{print m}')
    if (( longest > edge )); then convertArgs+=(-Z "$edge"); fi
  fi
  /usr/bin/sips "${convertArgs[@]}" "$source" --out "$temporary/result.jpg" >/dev/null
  base="${source:t:r}-$resultSuffix"
  destination="$folder/$base.jpg"
  index=2
  while ! /bin/ln "$temporary/result.jpg" "$destination" 2>/dev/null; do
    [[ -e "$destination" || -L "$destination" ]] || { print -u2 "Cannot create output: $destination"; exit 1; }
    destination="$folder/$base $index.jpg"
    (( index++ ))
  done
  /bin/rm -rf -- "$temporary"
  trap - EXIT
  print -r -- "$destination"
done
