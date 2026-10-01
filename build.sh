#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Whisper"
BRAND_DIR="$HOME/Library/Application Support/Whisper/Brand"
DISPLAY_NAME="$APP_NAME"
if [[ -f "$BRAND_DIR/name" ]]; then
    DISPLAY_NAME="$(cat "$BRAND_DIR/name")"
fi
ICON_SOURCE="Resources/icon-1024.png"
if [[ -f "$BRAND_DIR/icon-1024.png" ]]; then
    ICON_SOURCE="$BRAND_DIR/icon-1024.png"
fi
IDENTITY="Whisper Local Signing"
BUILD_DIR="build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

ensure_identity() {
    if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
        return
    fi
    echo "==> Creating self-signed code signing certificate '$IDENTITY'"
    local tmp
    tmp="$(mktemp -d)"
    cat >"$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" >/dev/null 2>&1
    openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/cert.p12" -passout pass:whisper >/dev/null 2>&1 \
        || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
            -out "$tmp/cert.p12" -passout pass:whisper
    security import "$tmp/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P whisper -T /usr/bin/codesign >/dev/null
    rm -rf "$tmp"
}

echo "==> Building release"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP/Contents/Info.plist"
if [[ -f "$BRAND_DIR/bundle-id" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(cat "$BRAND_DIR/bundle-id")" "$APP/Contents/Info.plist"
fi

if [[ ! -f Resources/icon-1024.png ]]; then
    swift Scripts/make-icon.swift Resources/icon-1024.png
fi
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

ensure_identity
echo "==> Signing"
if ! codesign --force --options runtime --entitlements Resources/Whisper.entitlements --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "    stable identity failed, falling back to ad-hoc (Accessibility will need re-granting after each build)"
    codesign --force --sign - "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to $INSTALL_DIR"
    pkill -x "$APP_NAME" 2>/dev/null || true
    TARGET="$INSTALL_DIR/$DISPLAY_NAME.app"
    rm -rf "$INSTALL_DIR/$APP_NAME.app" "$TARGET"
    cp -R "$APP" "$TARGET"
    touch "$TARGET"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET"
    open "$TARGET"
fi

echo "==> Done: $APP"
