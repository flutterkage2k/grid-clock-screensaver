// Renders the clock page and composes AppIcon.png, the 1024x1024 source for AppIcon.icns.
// The icon is the app drawing itself, frozen at ten past ten.
//
//   clang -fobjc-arc -framework Cocoa -framework WebKit -o /tmp/make_icon App/make_icon.m
//   /tmp/make_icon Webview/index.html App/AppIcon.png
//
// Then rebuild the .icns: sips each size into an AppIcon.iconset directory
// (16, 32, 32, 64, 128, 256, 256, 512, 512, 1024) and run
//   iconutil -c icns AppIcon.iconset -o App/AppIcon.icns
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Freeze the clock at ten past ten and lift the unlit glyphs so the grid still
// reads as texture once the icon is scaled down to 16pt.
static NSString * const kIconScript =
@"for (var i = 1; i < 5000; i++) clearInterval(i);"
 "var s = document.createElement('style');"
 "s.textContent = 'glyph{color:#464646;transition:none;font-weight:400}"
 ".on glyph{color:#fff;font-weight:500;text-shadow:0 0 0.9vh rgba(255,255,255,.75)}';"
 "document.head.appendChild(s);"
 "document.querySelectorAll('*').forEach(function(e){e.classList.remove('on')});"
 "document.querySelectorAll('.prefix')[9].classList.add('on');"
 "document.querySelector('.minutes').classList.add('on');"
 "document.querySelector('.past').classList.add('on');"
 "document.querySelectorAll('.suffix')[9].classList.add('on');"
 "'ok'";

static NSImage *ComposeIcon(NSImage *render, CGFloat canvas, CGFloat inset, CGFloat radius) {
    NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(canvas, canvas)];
    [icon lockFocusFlipped:NO];

    NSRect body = NSMakeRect(inset, inset, canvas - inset * 2, canvas - inset * 2);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:body xRadius:radius yRadius:radius];

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    shadow.shadowOffset = NSMakeSize(0, -canvas * 0.012);
    shadow.shadowBlurRadius = canvas * 0.028;
    [shadow set];
    [NSColor.blackColor setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];

    // The page only leaves a 4% margin around the grid, which the corner radius would
    // eat into, so pull the render in far enough to clear the corners.
    NSRect gridRect = NSInsetRect(body, NSWidth(body) * 0.075, NSHeight(body) * 0.075);

    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    [render drawInRect:gridRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    [icon unlockFocus];
    return icon;
}

static void WritePNG(NSImage *image, CGFloat pixels, NSString *path) {
    NSBitmapImageRep *rep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:pixels pixelsHigh:pixels
                                             bitsPerSample:8 samplesPerPixel:4
                                                  hasAlpha:YES isPlanar:NO
                                            colorSpaceName:NSCalibratedRGBColorSpace
                                               bytesPerRow:0 bitsPerPixel:0];
    rep.size = NSMakeSize(pixels, pixels);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    [image drawInRect:NSMakeRect(0, 0, pixels, pixels)];
    [NSGraphicsContext restoreGraphicsState];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSURL *indexURL = [NSURL fileURLWithPath:@(argv[1])];
    NSString *outPath = @(argv[2]);

    NSRect frame = NSMakeRect(0, 0, 1024, 1024);
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:[[WKWebViewConfiguration alloc] init]];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.contentView = webView;
    [window orderFront:nil];
    [webView loadFileURL:indexURL allowingReadAccessToURL:indexURL.URLByDeletingLastPathComponent];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:kIconScript completionHandler:^(id r, NSError *e) {
            if (e) { NSLog(@"FAIL script: %@", e); exit(1); }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                WKSnapshotConfiguration *snap = [[WKSnapshotConfiguration alloc] init];
                snap.snapshotWidth = @1024;
                [webView takeSnapshotWithConfiguration:snap completionHandler:^(NSImage *render, NSError *se) {
                    if (!render) { NSLog(@"FAIL snapshot: %@", se); exit(1); }
                    NSLog(@"render %@ reps=%@", NSStringFromSize(render.size), render.representations);
                    // Big Sur+ geometry: 824pt body centred in a 1024pt canvas.
                    NSImage *icon = ComposeIcon(render, 1024, 100, 185.4);
                    WritePNG(icon, 1024, outPath);
                    NSLog(@"wrote %@", outPath);
                    exit(0);
                }];
            });
        }];
    });
    [NSApp run];
    return 0;
}}
