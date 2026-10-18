#!/bin/zsh
# GitHub Release için ClockDraw-<sürüm>.dmg üretir.
#   zsh make_release.sh 0.3
#
# Çıkan DMG açılınca klasik Mac kurulum penceresi gelir:
# solda ClockDraw.app, sağda Applications kısayolu → sürükle bırak, kuruldu.
set -e
cd "$(dirname "$0")"

VERSION=${1:?Kullanım: zsh make_release.sh <sürüm>   (ör. 0.3)}
DMG="ClockDraw-$VERSION.dmg"

# 1) Uygulamayı bu sürüm numarasıyla derle (kurmadan)
VERSION=$VERSION zsh build_app.sh --no-install

# 2) DMG'nin içeriğini geçici bir klasörde hazırla
STAGE=$(mktemp -d)/ClockDraw
mkdir -p $STAGE
cp -R ClockDraw.app $STAGE/
ln -s /Applications $STAGE/Applications     # sürükle-bırak hedefi

# 3) hdiutil: macOS'un disk imajı aracı.
#    UDZO = sıkıştırılmış, salt okunur imaj (dağıtım için standart format)
rm -f $DMG
hdiutil create -volname "ClockDraw $VERSION" -srcfolder $STAGE -ov -format UDZO $DMG

echo ""
echo "Hazır: $(pwd)/$DMG"
echo "GitHub → Releases → Draft a new release → tag v$VERSION → bu dosyayı sürükle."
