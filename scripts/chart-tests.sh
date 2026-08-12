#!/bin/zsh
# Проверки ядра графика. Ядро намеренно не тянет SwiftUI и SwiftData, поэтому
# собирается обычным swiftc и гоняется за секунду — без симулятора и Xcode.
set -e
ROOT=${0:A:h:h}
SRC="$ROOT/ios/Sources/Chart"
OUT="${TMPDIR:-/tmp}/libra-chart-tests"
mkdir -p "$OUT"
swiftc -O \
  "$SRC/ChartWindow.swift" "$SRC/BrushLayout.swift" \
  "$SRC/WeightTimeline.swift" "$SRC/WeightAxis.swift" \
  "$ROOT/scripts/chart-tests/main.swift" -o "$OUT/run"
"$OUT/run"
