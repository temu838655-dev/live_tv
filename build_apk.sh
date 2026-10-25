#!/bin/sh
# Build APK cho ung dung "Truyen hinh". Dung chung cho may ca nhan va GitHub Actions.
#
#   Chay trong thu muc goc cua du an:   sh build_apk.sh
#
# Bien moi truong tuy chon:
#   TMDB_KEY, YOUTUBE_KEY      khoa API, duoc nhung vao app luc build
#   BUILD_NAME, BUILD_NUMBER   phien ban hien thi (vd 1.2.0) / so phien ban noi bo (tang dan)
#   KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
#                              ky APK bang khoa rieng. Neu khong co: ky bang khoa debug
#                              (cai duoc, nhung moi lan build chu ky khac nhau).
#
# Ket qua: dist/live_tv-<phien ban>.apk
set -eu
cd "$(dirname "$0")"

APP_LABEL="Truyền hình"
MIN_SDK=24

command -v flutter >/dev/null 2>&1 || {
  echo "Loi: chua cai Flutter (hoac chua them vao PATH)." >&2
  exit 1
}

# 1. Tao khung du an Android (khong ghi de lib/ va pubspec.yaml da co)
flutter create --platforms=android --project-name live_tv .

# 1b. Dat ma nguon vao lib/ (neu main.dart nam o thu muc goc, de de tai len bang dien thoai)
if [ -f main.dart ]; then
  mkdir -p lib
  cp main.dart lib/main.dart
fi

# 2. Sua AndroidManifest: quyen Internet, cho phep http (nhieu luong TV dung http), ten app
M=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$M" ||
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"
grep -q usesCleartextTraffic "$M" ||
  sed -i 's|<application|<application android:usesCleartextTraffic="true"|' "$M"
sed -i "s|android:label=\"[^\"]*\"|android:label=\"$APP_LABEL\"|" "$M"

# 3. Dam bao minSdk >= 24 (webview/video can API moi hon mac dinh cua mot so ban Flutter)
G=android/app/build.gradle.kts
[ -f "$G" ] || G=android/app/build.gradle
if grep -Eq '(maxOf|Math\.max)\(flutter\.minSdkVersion' "$G"; then
  :   # da sua tu lan chay truoc
elif grep -q 'flutter\.minSdkVersion' "$G"; then
  case "$G" in
    *.kts) sed -i "s|flutter\.minSdkVersion|maxOf(flutter.minSdkVersion, $MIN_SDK)|" "$G" ;;
    *)     sed -i "s|flutter\.minSdkVersion|Math.max(flutter.minSdkVersion, $MIN_SDK)|" "$G" ;;
  esac
else
  echo "Canh bao: khong thay minSdk trong $G, giu nguyen." >&2
fi

# 4. Icon app (chi can ban xxxhdpi, Android tu thu nho cho man hinh nho hon)
if [ -f ic_launcher.png ] && [ -f ic_launcher_foreground.png ]; then
  R=android/app/src/main/res
  rm -f "$R"/mipmap-*/ic_launcher.png
  mkdir -p "$R/mipmap-xxxhdpi" "$R/mipmap-anydpi-v26" "$R/values"
  cp ic_launcher.png "$R/mipmap-xxxhdpi/ic_launcher.png"
  cp ic_launcher_foreground.png "$R/mipmap-xxxhdpi/ic_launcher_foreground.png"
  cat > "$R/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF
  cat > "$R/values/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0E0F14</color>
</resources>
EOF
fi

# 5. Phien ban
PUB_VER=$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' pubspec.yaml | head -n 1)
: "${BUILD_NAME:=${PUB_VER%%+*}}"

# 6. Build
flutter pub get

set -- build apk --release --target-platform android-arm,android-arm64
set -- "$@" --build-name="$BUILD_NAME"
if [ -n "${BUILD_NUMBER:-}" ]; then
  set -- "$@" --build-number="$BUILD_NUMBER"
fi
if [ -n "${TMDB_KEY:-}" ]; then
  set -- "$@" "--dart-define=TMDB_KEY=$TMDB_KEY"
  echo "Nhung khoa TMDB: co"
else
  echo "Nhung khoa TMDB: khong (tab Thong tin phim se hien huong dan)"
fi
if [ -n "${YOUTUBE_KEY:-}" ]; then
  set -- "$@" "--dart-define=YOUTUBE_KEY=$YOUTUBE_KEY"
  echo "Nhung khoa YouTube: co"
else
  echo "Nhung khoa YouTube: khong (phim YouTube se bi an)"
fi

flutter "$@"

# 7. Gom ket qua vao dist/ va ky (neu co khoa rieng)
SRC=build/app/outputs/flutter-apk/app-release.apk
[ -f "$SRC" ] || {
  echo "Loi: khong thay $SRC" >&2
  exit 1
}
mkdir -p dist
OUT="dist/live_tv-${BUILD_NAME}.apk"
cp "$SRC" "$OUT"

if [ -n "${KEYSTORE_FILE:-}" ]; then
  [ -f "$KEYSTORE_FILE" ] || { echo "Loi: khong thay KEYSTORE_FILE=$KEYSTORE_FILE" >&2; exit 1; }
  [ -n "${KEYSTORE_PASSWORD:-}" ] && [ -n "${KEY_ALIAS:-}" ] || {
    echo "Loi: thieu KEYSTORE_PASSWORD hoac KEY_ALIAS." >&2
    exit 1
  }
  KEY_PASSWORD="${KEY_PASSWORD:-$KEYSTORE_PASSWORD}"
  export KEYSTORE_PASSWORD KEY_PASSWORD

  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  APKSIGNER=$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n 1 || true)
  [ -n "$APKSIGNER" ] || { echo "Loi: khong tim thay apksigner trong Android SDK." >&2; exit 1; }

  "$APKSIGNER" sign --ks "$KEYSTORE_FILE" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass env:KEYSTORE_PASSWORD --key-pass env:KEY_PASSWORD "$OUT"
  "$APKSIGNER" verify --print-certs "$OUT" | head -n 3
  echo "Da ky bang khoa rieng."
else
  echo "Ky bang khoa debug (muon cap nhat de len ban cu thi xem muc 'Ky APK' trong README)."
fi

ls -lh "$OUT"
echo "APK: $OUT"
