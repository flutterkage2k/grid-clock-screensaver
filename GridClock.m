#import "GridClock.h"

static NSString * const kModuleName = @"com.chrstphrknwtn.grid-clock";
static NSString * const kScreenDisplayOptionKey = @"screenDisplayOption";
static NSString * const kBrightnessKey = @"brightness";

static const NSInteger kMinBrightness = 5;
static const NSInteger kMaxBrightness = 100;

typedef NS_ENUM(NSInteger, GridClockScreenDisplayOption) {
    GridClockScreenDisplayPrimary = 0,
    GridClockScreenDisplayMain = 1,
    GridClockScreenDisplayAll = 2
};

@interface GridClock ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) NSInteger brightnessBeforeEditing;
@end

@implementation GridClock

+ (ScreenSaverDefaults *)defaults {
    return [ScreenSaverDefaults defaultsForModuleWithName:kModuleName];
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    if (!(self = [super initWithFrame:frame isPreview:isPreview])) return nil;

    [[GridClock defaults] registerDefaults:@{
        kScreenDisplayOptionKey: @(GridClockScreenDisplayPrimary),
        kBrightnessKey: @(kMaxBrightness)
    }];

    // Black backing avoids a white flash before index.html paints.
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;

    self.animationTimeInterval = 1.0 / 30.0;

    [self addSubview:self.webView];

    return self;
}

- (WKWebView *)webView {
    if (_webView) return _webView;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.suppressesIncrementalRendering = YES;

    _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    _webView.hidden = YES; // Revealed in -viewDidMoveToWindow once the screen is known.
    if (@available(macOS 12.0, *)) {
        _webView.underPageBackgroundColor = NSColor.blackColor;
    }

    NSURL *indexURL = [[NSBundle bundleForClass:self.class] URLForResource:@"index"
                                                             withExtension:@"html"
                                                              subdirectory:@"Webview"];
    if (indexURL) {
        [_webView loadFileURL:indexURL allowingReadAccessToURL:indexURL.URLByDeletingLastPathComponent];
    } else {
        NSLog(@"GridClock: Webview/index.html missing from bundle resources");
    }

    return _webView;
}

#pragma mark - Screen selection

// macOS runs one screen saver instance per display, so the display choice has to be
// resolved from the window's own screen rather than by comparing frame origins.
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        self.webView.hidden = !self.shouldDisplayOnCurrentScreen;
    }
}

- (BOOL)shouldDisplayOnCurrentScreen {
    if (self.isPreview) return YES;

    // nil means the host put this window off-screen entirely (see readme, multi-display
    // note); nothing is visible either way, so do not also hide the content.
    NSScreen *screen = self.window.screen;
    if (!screen) return YES;

    switch ([[GridClock defaults] integerForKey:kScreenDisplayOptionKey]) {
        case GridClockScreenDisplayPrimary:
            // The screen the menu bar lives on (System Settings > Displays > Arrangement).
            return [screen isEqual:NSScreen.screens.firstObject];
        case GridClockScreenDisplayMain:
            return [screen isEqual:NSScreen.mainScreen];
        case GridClockScreenDisplayAll:
        default:
            return YES;
    }
}

#pragma mark - Brightness

- (void)applyBrightness:(NSInteger)percent {
    percent = MAX(kMinBrightness, MIN(kMaxBrightness, percent));
    NSString *script = [NSString stringWithFormat:
                        @"document.documentElement.style.setProperty('--brightness', '%.2f')",
                        percent / (double)kMaxBrightness];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

#pragma mark - ScreenSaverView

// The clock ticks itself from JavaScript; nothing to draw per frame.
- (void)animateOneFrame {}

#pragma mark - Configure sheet

- (BOOL)hasConfigureSheet { return YES; }

- (NSWindow *)configureSheet {
    if (!_configSheet) {
        // +[NSBundle loadNibNamed:owner:] looks in the *host app* bundle, which for a
        // screen saver is System Settings, not the .saver. Load from our own bundle.
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        if (![bundle loadNibNamed:@"ConfigureSheet" owner:self topLevelObjects:nil]) {
            NSLog(@"GridClock: failed to load ConfigureSheet.xib");
            return nil;
        }
    }

    ScreenSaverDefaults *defaults = [GridClock defaults];
    [self.screenDisplayOption selectItemAtIndex:[defaults integerForKey:kScreenDisplayOptionKey]];

    self.brightnessBeforeEditing = [defaults integerForKey:kBrightnessKey];
    self.brightnessSlider.integerValue = self.brightnessBeforeEditing;

    return _configSheet;
}

// Continuous, so the preview dims while the slider is dragged.
- (IBAction)brightnessChanged:(id)sender {
    [self applyBrightness:self.brightnessSlider.integerValue];
}

- (IBAction)cancelClick:(id)sender {
    [self applyBrightness:self.brightnessBeforeEditing];
    [self closeConfigureSheet];
}

- (IBAction)okClick:(id)sender {
    ScreenSaverDefaults *defaults = [GridClock defaults];
    [defaults setInteger:self.screenDisplayOption.indexOfSelectedItem forKey:kScreenDisplayOptionKey];
    [defaults setInteger:self.brightnessSlider.integerValue forKey:kBrightnessKey];
    [defaults synchronize];

    self.webView.hidden = !self.shouldDisplayOnCurrentScreen;

    [self closeConfigureSheet];
}

- (void)closeConfigureSheet {
    NSWindow *parent = _configSheet.sheetParent;
    if (parent) {
        [parent endSheet:_configSheet];
    } else {
        [_configSheet close];
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self applyBrightness:[[GridClock defaults] integerForKey:kBrightnessKey]];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"GridClock: navigation failed: %@", error);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"GridClock: provisional navigation failed: %@", error);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    NSLog(@"GridClock: web content process terminated, reloading");
    [webView reload];
}

#pragma mark - Input passthrough

- (NSView *)hitTest:(NSPoint)aPoint { return self; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseEntered:(NSEvent *)event {}
- (void)mouseExited:(NSEvent *)event {}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return NO; }

@end
