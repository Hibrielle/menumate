#!/bin/zsh
# Total size of the selected items, copied to the clipboard.
# Demonstrates: reading $@, shelling out to du, stdout first line as the success summary.
emulate -L zsh
total=$(du -ch "$@" 2>/dev/null | tail -1 | cut -f1)
printf '%s' "$total" | pbcopy
print "Total ${total} (copied)"
