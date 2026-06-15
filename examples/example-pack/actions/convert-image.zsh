#!/bin/zsh
# Convert each selected image to the format chosen in the submenu, writing alongside the original.
# Demonstrates: a submenu (manifest `variants.fixed`) whose value arrives via $MENUMATE_VARIANT;
# UTI gating (manifest `utis: ["public.image"]`) so it only appears on images.
emulate -L zsh
fmt="${MENUMATE_VARIANT:?no target format}"
n=0
for p in "$@"; do
  out="${p:r}.${fmt}"
  sips -s format "$fmt" "$p" --out "$out" >/dev/null 2>&1 && (( n++ ))
done
print "Converted ${n} image(s) to ${fmt}"
