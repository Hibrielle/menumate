#!/bin/zsh
# Copy the base name (without extension) of each selected file, one per line.
# Demonstrates: positional args ($@), zsh modifiers (:t tail, :r root), pbcopy, stdout summary.
emulate -L zsh
names=()
for p in "$@"; do names+=("${p:t:r}"); done
printf '%s\n' "${names[@]}" | pbcopy
print "Copied ${#names[@]} name(s)"
