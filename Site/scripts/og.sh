#!/bin/sh
# Renders the Open Graph images in public/ (1200 × 630) from inline SVG with rsvg-convert
# (`brew install librsvg`). Run from Site/ after the mark, a name or a headline changes:
#   sh scripts/og.sh
# Each card is the site in miniature: the mark and "Stadig", a headline, a line under it, and
# the ruler with a reading on it.
set -eu
cd "$(dirname "$0")/.."

INK="#0d0e10"; PAPER="#f4f2ee"; TEXT2="#b1b2ad"; TEXT3="#8d8f8a"; TRACK="#2a2d32"; GOOD="#3ecf8e"

# card <file> <accent> <value> <gain> <line 1> <line 2 or ""> <subtitle>
card() {
  file=$1; accent=$2; value=$3; gain=$4; l1=$5; l2=$6; sub=$7
  x0=72; w=1056; bar_y=448; bar_h=60
  fill_w=$(( w * (value - gain) / 100 )); gain_w=$(( w * gain / 100 )); mark_x=$(( x0 + w * value / 100 ))
  segs=""; i=1
  while [ $i -lt 10 ]; do sx=$(( x0 + w * i / 10 - 1 )); segs="$segs<rect x=\"$sx\" y=\"$bar_y\" width=\"3\" height=\"$bar_h\" fill=\"$INK\"/>"; i=$((i + 1)); done
  ticks=""; i=0
  while [ $i -le 100 ]; do
    tx=$(( x0 + w * i / 100 )); if [ $((i % 10)) -eq 0 ]; then th=14; elif [ $((i % 5)) -eq 0 ]; then th=9; else th=5; fi
    ticks="$ticks<rect x=\"$tx\" y=\"$((bar_y + bar_h + 12))\" width=\"1.5\" height=\"$th\" fill=\"$TEXT3\"/>"; i=$((i + 1))
  done
  if [ -n "$l2" ]; then
    title="<text x=\"72\" y=\"236\" class=\"t\">$l1</text><text x=\"72\" y=\"318\" class=\"t\">$l2</text>"; sub_y=378
  else
    title="<text x=\"72\" y=\"290\" class=\"t\">$l1</text>"; sub_y=350
  fi
  svg=$(mktemp)
  cat > "$svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <style>
    .t { font: 700 76px "Helvetica Neue"; letter-spacing: -3px; fill: $PAPER; }
    .s { font: 400 32px "Helvetica Neue"; fill: $TEXT2; }
    .b { font: 700 40px "Helvetica Neue"; letter-spacing: -1px; fill: $PAPER; }
    .d { font: 400 26px "Helvetica Neue"; fill: $TEXT3; }
  </style>
  <rect width="1200" height="630" fill="$INK"/>
  <rect x="72" y="72" width="64" height="64" rx="14" fill="$PAPER"/>
  <path d="M88 113h32" stroke="$INK" stroke-width="6" stroke-linecap="round"/>
  <circle cx="104" cy="97" r="6" fill="$INK"/>
  <text x="156" y="118" class="b">Stadig</text>
  <text x="1128" y="118" class="d" text-anchor="end">stadig.dev</text>
  $title
  <text x="72" y="$sub_y" class="s">$sub</text>
  <clipPath id="bar"><rect x="$x0" y="$bar_y" width="$w" height="$bar_h" rx="10"/></clipPath>
  <g clip-path="url(#bar)">
    <rect x="$x0" y="$bar_y" width="$w" height="$bar_h" fill="$TRACK"/>
    <rect x="$x0" y="$bar_y" width="$fill_w" height="$bar_h" fill="$accent"/>
    <rect x="$((x0 + fill_w))" y="$bar_y" width="$gain_w" height="$bar_h" fill="$GOOD"/>
    $segs
  </g>
  <rect x="$((mark_x - 1))" y="$((bar_y - 10))" width="3" height="$((bar_h + 20))" fill="$PAPER"/>
  $ticks
</svg>
SVG
  rsvg-convert -w 1200 -h 630 "$svg" -o "public/$file"
  rm "$svg"
  echo "public/$file"
}

card og.png "#6d8bff" 57 2 "Six scores that move" "when you do the work." "Stadig Lift and Stadig Macro. Both free."
card og-lift.png "#6d8bff" 57 2 "Stadig Lift" "" "A program that writes itself around you."
card og-macro.png "#3ecf8e" 92 0 "Stadig Macro" "" "Spend less time in your food app."
