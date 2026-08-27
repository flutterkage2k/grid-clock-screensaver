# Grid Clock
Grid clock for macOS - as a standalone app, or as a screen saver.

![Grid Clock Screenshot](GridClock.png)

## App
A full-screen black clock on every display, meant for leaving up overnight instead of
shutting the machine down. It keeps the displays awake and is unaffected by the screen
saver bug described below.

```
./make_app.sh
open "build/Grid Clock.app"
```

| Key | |
| --- | --- |
| `esc` or `cmd-Q` | quit |
| `up` / `down` | brightness, 5-100% in steps of 5, remembered between launches |

The icon is the clock rendering itself, frozen at ten past ten - `App/make_icon.m`
regenerates `App/AppIcon.png` from the same page the app displays.

Drag `build/Grid Clock.app` to `/Applications` to keep it. Only Xcode's command line
tools are needed - `make_app.sh` is a plain `clang` invocation.

## Screen saver
Requires Xcode.

```
xcodebuild -project "Grid Clock.xcodeproj" -scheme "Grid Clock" -configuration Release -derivedDataPath ./build
cp -R "build/Build/Products/Release/Grid Clock.saver" ~/Library/Screen\ Savers/
```

Then pick **Grid Clock** in System Settings > Screen Saver > Other. Options has the
display choice and a brightness slider. Read the multi-display note below first.

Prebuilt `.saver` from upstream: [0.0.5](https://github.com/chrstphrknwtn/grid-clock-screensaver/releases/download/0.0.5/Grid.Clock.0.0.5.saver.zip) (does not run on modern macOS).

## Fork notes
This fork updates the 2018 original to run on current macOS (tested on macOS 26.6.2 Tahoe, Xcode 26.6, Apple Silicon):

- Replaced the removed legacy `WebView` with `WKWebView`, loading the bundled page via `-loadFileURL:allowingReadAccessToURL:`.
- Fixed the configure sheet: the nib is now loaded from the saver's own bundle (`+[NSBundle loadNibNamed:owner:]` looked in the host app), and the sheet is dismissed via `-[NSWindow endSheet:]` instead of the long-removed `NSApplication` equivalent.
- Display selection is resolved from the window's own `NSScreen` instead of comparing frame origins, which no longer works now that macOS runs one saver instance per display.
- Deployment target raised to macOS 11, ad-hoc code signing enabled, Carbon `Rez` build phase removed.
- Added a **Brightness** slider (5-100%) in Options, for leaving the clock up overnight.

- Added the standalone app, because the screen saver could not be made reliable on
  a multi-display setup (below).

## Known issue: the screen saver on multiple displays
`legacyScreenSaver` hands each saver window a frame whose origin is in CoreGraphics
coordinates (y grows downward from the top-left of the primary display) while AppKit
reads it as y-up. Displays arranged side by side are unaffected because their origin
is y=0 either way, but a display placed above or below the primary gets a window in
empty space - `window.screen` is `nil` and that display shows the system background
instead of the saver:

```
window frame handed to the saver   {{-305, -1440}, {3440, 1440}}
where that display actually is     {{-305,  1692}, {3440, 1440}}
```

A saver bundle cannot correct this. It runs inside an app extension whose window is
owned by the host process, so `-[NSWindow setFrame:]` and `-setFrameOrigin:` are both
silently ignored. Arranging the displays side by side in System Settings > Displays >
Arrangement avoids it; otherwise use the app.

The build is arm64-only by default (Xcode 26's standard architectures). For a universal binary, set `ARCHS = "arm64 x86_64"`.

## Related
- [Epoch Flip Clock Screensaver](https://github.com/chrstphrknwtn/epoch-flip-clock-screensaver)
- [Word Clock Screensaver](https://github.com/chrstphrknwtn/word-clock-screensaver)
