#!/bin/bash
# ============================================================
# StickyTodo 一键编译打包脚本
# 用法:
#   ./build.sh            # 仅编译并组装 .app 到 build/
#   ./build.sh zip        # 额外生成 StickyTodo-<版本>-macOS.zip
#   ./build.sh dmg        # 额外生成 StickyTodo-<版本>-macOS.dmg
#   ./build.sh all        # zip + dmg 全量发布包
# ============================================================
set -euo pipefail

VERSION="1.0.0"
APP_NAME="StickyTodo"
SRC="StickyTodo.swift"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> [1/5] 编译 $SRC (swiftc -O)"

# CLT 无 Xcode 环境需要 VFS overlay 屏蔽 SwiftBridging modulemap 冲突。
# 若已安装完整 Xcode，可直接改用:
#   swiftc -O -parse-as-library -framework SwiftUI -framework AppKit -framework UserNotifications -o "$BUILD_DIR/$APP_NAME" "$SRC"
# 并跳过下面的 vfs 分支。
USE_VFS=0
if [ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ] && ! xcode-select -p 2>/dev/null | grep -q "\.app/"; then
    USE_VFS=1
    VFS_YAML="$BUILD_DIR/vfs-file.yaml"
    EMPTY_MODULE="$BUILD_DIR/empty.swiftmodule"
    mkdir -p "$BUILD_DIR"
    touch "$EMPTY_MODULE"
    VFS_ABS="$(cd "$BUILD_DIR" && pwd)/vfs-file.yaml"
    EMPTY_ABS="$(cd "$BUILD_DIR" && pwd)/empty.swiftmodule"
    cat > "$VFS_YAML" <<EOF
{
  "version": 0,
  "case-sensitive": "true",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
      "type": "file",
      "external-contents": "$EMPTY_ABS",
      "use-external-name": "true"
    }
  ]
}
EOF
fi

mkdir -p "$BUILD_DIR"

if [ "$USE_VFS" -eq 1 ]; then
    echo "==>   使用 VFS overlay: $VFS_ABS"
    swiftc -O -parse-as-library \
        -Xfrontend -vfsoverlay -Xfrontend "$VFS_ABS" \
        -framework SwiftUI -framework AppKit -framework UserNotifications \
        -o "$BUILD_DIR/$APP_NAME" "$SRC"
else
    swiftc -O -parse-as-library \
        -framework SwiftUI -framework AppKit -framework UserNotifications \
        -o "$BUILD_DIR/$APP_NAME" "$SRC"
fi

echo "==> [2/5] 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Info.plist: 若仓库根目录存在则使用，否则生成最小版本
if [ -f "Info.plist" ]; then
    cp Info.plist "$APP_DIR/Contents/"
else
    cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.marvis.stickytodo</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>便签Todo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
fi

# AppIcon: 若存在则复制
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/"
    # Info.plist 中声明图标（若用户 Info.plist 有 CFBundleIconFile 则保留）
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> [3/5] ad-hoc 签名"
codesign --force --deep --sign - "$APP_DIR"

echo "==> [4/5] 校验"
codesign --verify --deep "$APP_DIR"
echo "    OK: $APP_DIR"

# ============================================================
# 打包
# ============================================================
make_zip() {
    echo "==> [5/5] 生成 zip"
    ZIP_NAME="$APP_NAME-$VERSION-macOS.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$BUILD_DIR/$ZIP_NAME"
    echo "    OK: $BUILD_DIR/$ZIP_NAME"
}

make_dmg() {
    echo "==> [5/5] 生成 dmg"
    DMG_NAME="$APP_NAME-$VERSION-macOS.dmg"
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_DIR" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
    rm -rf "$DMG_STAGING"
    echo "    OK: $BUILD_DIR/$DMG_NAME"
}

case "${1:-}" in
    zip)  make_zip ;;
    dmg)  make_dmg ;;
    all)  make_zip; make_dmg ;;
    *)    echo "==> 完成。可用 ./build.sh {zip|dmg|all} 生成发布包" ;;
esac
