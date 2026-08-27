#!/bin/sh
# Builds "Grid Clock.app" - the standalone clock, for leaving up overnight.
# The screen saver is built with xcodebuild instead; see readme.md.
set -e
cd "$(dirname "$0")"

APP="build/Grid Clock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp App/Info.plist "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/"
cp -R Webview "$APP/Contents/Resources/"

clang -fobjc-arc -Os -Wall -mmacosx-version-min=11.0 \
      -framework Cocoa -framework WebKit \
      -o "$APP/Contents/MacOS/Grid Clock" App/main.m

codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
