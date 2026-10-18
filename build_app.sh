#!/bin/zsh
# ClockDraw.app paketini üretir ve /Applications'a kurar.
#   zsh build_app.sh            → derle + paketle + /Applications'a kopyala
#   zsh build_app.sh --no-install → sadece proje klasöründe ClockDraw.app üret
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-0.3}     # dışarıdan verilebilir: VERSION=0.4 zsh build_app.sh

# 1) Release derlemesi: optimizasyonlu, hata ayıklama bilgisi az → küçük ve hızlı
swift build -c release

# 2) .app aslında belirli düzende bir klasör:
#    ClockDraw.app/Contents/MacOS/ClockDraw   → çalıştırılabilir dosya
#    ClockDraw.app/Contents/Info.plist       → kimlik kartı (isim, kimlik, Dock'ta görünme vb.)
APP=ClockDraw.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/ClockDraw $APP/Contents/MacOS/

# İkon: asset catalog'daki PNG'ler zaten .iconset adlandırmasında (icon_16x16.png, icon_16x16@2x.png...).
# iconutil (macOS'la gelir) bunları tek bir .icns dosyasında birleştirir.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p $ICONSET
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png $ICONSET/
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClockDraw</string>
  <key>CFBundleIdentifier</key><string>com.erentatar.clockdraw</string>
  <key>CFBundleExecutable</key><string>ClockDraw</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# 3) Ad-hoc imza ("-" = sertifikasız, sadece bu Mac için).
#    Apple Silicon imzasız kodu hiç çalıştırmaz; paket bütün olarak imzalanmalı.
codesign --force --sign - $APP

# 4) Kurulum
if [[ "$1" != "--no-install" ]]; then
  pkill -x ClockDraw 2>/dev/null || true      # açıksa kapat (eski sürüm dosyayı tutmasın)
  # Eski adla (SaatPlan) kurulmuş sürüm varsa kaldır
  pkill -x SaatPlan 2>/dev/null || true
  rm -rf /Applications/SaatPlan.app
  rm -rf /Applications/$APP
  cp -R $APP /Applications/
  open /Applications/$APP
  echo "Kuruldu ve açıldı: /Applications/$APP"
else
  echo "Hazır: $(pwd)/$APP"
fi
