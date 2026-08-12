#!/bin/zsh
# Собирает BLEScan.app — минимальную .app-обёртку вокруг питона.
#
# Зачем: macOS убивает процесс, который трогает Bluetooth, если в Info.plist нет
# NSBluetoothAlwaysUsageDescription. У интерпретатора такого ключа нет, поэтому
# сканировать эфир «просто питоном» нельзя — процесс падает с SIGABRT (namespace TCC).
#
# Запуск:  ./scripts/make-ble-app.sh
set -e
cd "$(dirname "$0")/.."

if [ ! -d .venv ]; then
    python3 -m venv .venv
fi
./.venv/bin/pip install -q --upgrade pip bleak

REAL_PYTHON=$(./.venv/bin/python -c 'import sys, os; print(os.path.realpath(sys.executable))')
BASE_PREFIX=$(./.venv/bin/python -c 'import sys; print(sys.base_prefix)')
PY_VERSION=$(./.venv/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')

rm -rf BLEScan.app
mkdir -p BLEScan.app/Contents/MacOS BLEScan.app/Contents/lib
cp "$REAL_PYTHON" BLEScan.app/Contents/MacOS/python3

# Contents/ становится корнем venv — тогда питон сам находит и stdlib, и bleak,
# без PYTHONHOME и PYTHONPATH.
printf 'home = %s/bin\ninclude-system-site-packages = false\nversion = %s\n' \
    "$BASE_PREFIX" "$PY_VERSION" > BLEScan.app/Contents/pyvenv.cfg
ln -sfn "../../../.venv/lib/python$PY_VERSION" "BLEScan.app/Contents/lib/python$PY_VERSION"

cat > BLEScan.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BLEScan</string>
  <key>CFBundleDisplayName</key><string>BLE Scale Sniffer</string>
  <key>CFBundleIdentifier</key><string>com.example.blescan</string>
  <key>CFBundleExecutable</key><string>python3</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Чтение данных с умных весов по Bluetooth LE.</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>Чтение данных с умных весов по Bluetooth LE.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - BLEScan.app

echo "Готово. Запускать так (флаг -n обязателен):"
echo "  open -n -a \"\$PWD/BLEScan.app\" --args \"\$PWD/qnscale.py\" 8"
