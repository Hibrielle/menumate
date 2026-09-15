#!/bin/zsh
emulate -L zsh
set -euo pipefail
format=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract format raw -o - -)
quality=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract quality raw -o - -)
output=$(print -rn -- "$MENUMATE_INPUT" | /usr/bin/plutil -extract output raw -o - -)
[[ "$format" == png || "$format" == jpeg || "$format" == tiff ]] || { print -u2 'Invalid output format'; exit 2; }
[[ "$quality" == <-> && "$quality" -ge 10 && "$quality" -le 100 ]] || { print -u2 'Invalid JPEG quality'; exit 2; }
[[ "$output" == same || "$output" == subfolder ]] || { print -u2 'Invalid output location'; exit 2; }
(( $# > 0 )) || { print -u2 'No input images'; exit 2; }
resultSuffix=converted
resultFolder='Converted Images'
if [[ "${MENUMATE_LOCALE:-en}" == zh* ]]; then
  resultSuffix=转换
  resultFolder=转换图片
fi
extension="$format"
[[ "$format" == jpeg ]] && extension=jpg
for source in "$@"; do
  [[ -f "$source" ]] || { print -u2 "Missing input: $source"; exit 2; }
  inputFormat=$(/usr/bin/sips -g format "$source" | /usr/bin/awk '/format:/{print $2}')
  [[ "$inputFormat" == jpeg || "$inputFormat" == png || "$inputFormat" == tiff || "$inputFormat" == gif || "$inputFormat" == heic ]] || { print -u2 "Unsupported input image: $source"; exit 2; }
  folder="${source:h}"
  [[ "$output" == subfolder ]] && folder="$folder/$resultFolder"
  /bin/mkdir -p "$folder"
  temporary=$(/usr/bin/mktemp -d "$folder/.menumate-XXXXXXXX")
  trap '/bin/rm -rf -- "$temporary"' EXIT
  convertArgs=(-s format "$format")
  [[ "$format" == jpeg ]] && convertArgs+=(-s formatOptions "$quality")
  /usr/bin/sips "${convertArgs[@]}" "$source" --out "$temporary/result.$extension" >/dev/null
  base="${source:t:r}-$resultSuffix"
  destination="$folder/$base.$extension"
  index=2
  while ! /bin/ln "$temporary/result.$extension" "$destination" 2>/dev/null; do
    [[ -e "$destination" || -L "$destination" ]] || { print -u2 "Cannot create output: $destination"; exit 1; }
    destination="$folder/$base $index.$extension"
    (( index++ ))
  done
  /bin/rm -rf -- "$temporary"
  trap - EXIT
  print -r -- "$destination"
done
