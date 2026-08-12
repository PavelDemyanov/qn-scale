#!/bin/zsh
# Отрисовка значков приложения в icons/. Рисуются кодом: любой вариант можно
# поправить на пункт и пересобрать, а не переделывать в редакторе.
set -e
ROOT=${0:A:h:h}
OUT="${TMPDIR:-/tmp}/libra-icons"
mkdir -p "$OUT"
swiftc -O "$ROOT/scripts/icons/main.swift" -o "$OUT/render"
"$OUT/render"
