#!/bin/sh
# Resolve "GLYPH  label" for any command name from icons.tsv. No per-service
# code: add a row to the TSV to override; unknown names get a 2-letter badge.
# Usage: tab-icon.sh <command-name>
set -u
icondir=${ZELLIJ_ICONS_TSV:-$(dirname "$0")/icons.tsv}
raw=${1:-shell}
raw=${raw##*/}            # strip path
raw=${raw%.exe}           # strip windows suffix
lower_raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
name=$lower_raw
case $name in *[0-9]*) name=$(printf '%s' "$name" | sed 's/[0-9.]*$//');; esac
[ -n "$name" ] || name=shell

lookup() { # $1 = exact key -> "glyph<TAB>label"
  awk -F'\t' -v k="$1" '$1==k && !/^#/ {print $2 "\t" $3; exit}' "$icondir" 2>/dev/null
}
row=$(lookup "$lower_raw")
[ -n "$row" ] || row=$(lookup "$name")
# Only prefix-match on a delimiter so ssh/stable/substrings never match sh/git.
if [ -z "$row" ]; then
  row=$(awk -F'\t' -v k="$lower_raw" \
    'index($1,"-")>0 && k ~ "^" $1 "-" {print $2 "\t" $3; exit}' "$icondir" 2>/dev/null)
fi

if [ -n "$row" ]; then
  glyph=$(printf '%s' "$row" | cut -f1)
  label=$(printf '%s' "$row" | cut -f2)
  printf '%s  %s\n' "$glyph" "${label:-$raw}"
else
  badge=$(printf '%s' "$raw" | cut -c1-2 | tr '[:lower:]' '[:upper:]')
  printf '>%s  %s\n' "$badge" "$raw"
fi
