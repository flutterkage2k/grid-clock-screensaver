# Grid Clock
Grid clock macOS screensaver

![Grid Clock Screenshot](GridClock.png)

## Install
Build it yourself (requires Xcode):

```
xcodebuild -project "Grid Clock.xcodeproj" -scheme "Grid Clock" -configuration Release -derivedDataPath ./build
cp -R "build/Build/Products/Release/Grid Clock.saver" ~/Library/Screen\ Savers/
```

Then pick **Grid Clock** in System Settings > Screen Saver > Other.

Prebuilt `.saver` from upstream: [0.0.5](https://github.com/chrstphrknwtn/grid-clock-screensaver/releases/download/0.0.5/Grid.Clock.0.0.5.saver.zip) (does not run on modern macOS).

## Fork notes
This fork updates the 2018 original to run on current macOS (tested on macOS 26.6.2 Tahoe, Xcode 26.6, Apple Silicon):

- Replaced the removed legacy `WebView` with `WKWebView`, loading the bundled page via `-loadFileURL:allowingReadAccessToURL:`.
- Fixed the configure sheet: the nib is now loaded from the saver's own bundle (`+[NSBundle loadNibNamed:owner:]` looked in the host app), and the sheet is dismissed via `-[NSWindow endSheet:]` instead of the long-removed `NSApplication` equivalent.
- Display selection is resolved from the window's own `NSScreen` instead of comparing frame origins, which no longer works now that macOS runs one saver instance per display.
- Deployment target raised to macOS 11, ad-hoc code signing enabled, Carbon `Rez` build phase removed.
- Added a **Brightness** slider (5-100%) in Options, for leaving the clock up overnight.

## Known issue: displays stacked vertically
`legacyScreenSaver` hands each saver window a frame whose origin is in CoreGraphics
coordinates (y grows downward from the top-left of the primary display) while AppKit
reads it as y-up. Displays arranged side by side are unaffected because their origin
is y=0 either way, but a display placed above or below the primary gets a window in
empty space: `window.screen` is `nil` and that display shows the system background
instead of the saver. A saver bundle cannot correct this - it runs in an app extension
whose window frame is owned by the host process, so `-[NSWindow setFrame:]` and
`-setFrameOrigin:` are both ignored. Arranging the displays side by side in
System Settings > Displays > Arrangement avoids it.

The build is arm64-only by default (Xcode 26's standard architectures). For a universal binary, set `ARCHS = "arm64 x86_64"`.

## Related
- [Epoch Flip Clock Screensaver](https://github.com/chrstphrknwtn/epoch-flip-clock-screensaver)
- [Word Clock Screensaver](https://github.com/chrstphrknwtn/word-clock-screensaver)
