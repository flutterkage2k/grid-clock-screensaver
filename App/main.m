// Grid Clock, standalone app.
//
// Same clock page as the screen saver, but hosted in a plain app so it is not subject
// to legacyScreenSaver's window placement (see readme: displays stacked vertically).
// One black full-screen window per display, above everything, with the display kept awake.
//
//   esc / cmd-Q  quit
//   up / down    brightness

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <os/log.h>

static NSString * const kBrightnessKey = @"brightness";
static const NSInteger kMinBrightness = 5;
static const NSInteger kMaxBrightness = 100;
static const NSInteger kBrightnessStep = 5;

#pragma mark - Window

// A borderless window refuses key status by default, which would leave the app unable
// to see the escape and arrow keys.
@interface ClockWindow : NSWindow
@end

@implementation ClockWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

#pragma mark - Delegate

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property (nonatomic, strong) NSMutableArray<NSWindow *> *windows;
@property (nonatomic, strong) NSMutableArray<WKWebView *> *webViews;
@property (nonatomic, strong) id displayAwakeActivity;
@property (nonatomic, strong) NSTimer *tick;
@property (nonatomic, assign) NSInteger lastLoggedMinute;
@property (nonatomic, strong) id keyMonitor;
@end

@implementation AppDelegate

- (NSInteger)brightness {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kBrightnessKey] == nil) return kMaxBrightness;
    return MAX(kMinBrightness, MIN(kMaxBrightness, [defaults integerForKey:kBrightnessKey]));
}

- (void)setBrightness:(NSInteger)percent {
    percent = MAX(kMinBrightness, MIN(kMaxBrightness, percent));
    [NSUserDefaults.standardUserDefaults setInteger:percent forKey:kBrightnessKey];
    for (WKWebView *webView in self.webViews) {
        [self applyBrightnessTo:webView];
    }
}

- (void)applyBrightnessTo:(WKWebView *)webView {
    NSString *script = [NSString stringWithFormat:
                        @"document.documentElement.style.setProperty('--brightness', '%.2f')",
                        self.brightness / (double)kMaxBrightness];
    [webView evaluateJavaScript:script completionHandler:nil];
}

- (void)showHint:(NSString *)text {
    // Injected rather than baked into index.html so the page stays shared with the saver.
    NSString *script = [NSString stringWithFormat:
        @"(function(t){var h=document.getElementById('gc-hint');"
         "if(!h){h=document.createElement('div');h.id='gc-hint';"
         "h.style.cssText='position:fixed;left:0;right:0;bottom:4vh;text-align:center;z-index:9;"
         "font:300 1.5vh -apple-system,sans-serif;letter-spacing:.35em;text-transform:uppercase;"
         "color:#666;transition:opacity 1.2s ease-in-out;pointer-events:none';"
         "document.body.appendChild(h);}"
         "h.textContent=t;h.style.opacity='1';"
         "clearTimeout(window.__gcHint);"
         "window.__gcHint=setTimeout(function(){h.style.opacity='0';},4000);})(%@)",
        [self jsStringLiteral:text]];
    for (WKWebView *webView in self.webViews) {
        [webView evaluateJavaScript:script completionHandler:nil];
    }
}

- (NSString *)jsStringLiteral:(NSString *)text {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[text] options:0 error:nil];
    NSString *array = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return [array substringWithRange:NSMakeRange(1, array.length - 2)]; // strip the [ ]
}

#pragma mark Windows

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.windows = [NSMutableArray array];
    self.webViews = [NSMutableArray array];

    [self buildWindows];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(buildWindows)
                                               name:NSApplicationDidChangeScreenParametersNotification
                                             object:nil];

    __weak typeof(self) weakSelf = self;

    self.displayAwakeActivity =
        [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityIdleDisplaySleepDisabled |
                                                            NSActivityUserInitiated
                                                     reason:@"Showing the clock"];

    // index.js keeps its own setInterval, but WebKit naps the web content process once
    // the app is not frontmost, which stops that timer and leaves the last frame frozen
    // on screen. Driving updateClock() from here instead keeps the page ticking, because
    // the call itself wakes the process.
    self.tick = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                repeats:YES
                                                  block:^(NSTimer *timer) { [weakSelf tickClock]; }];
    self.tick.tolerance = 0.2;
    [NSRunLoop.mainRunLoop addTimer:self.tick forMode:NSRunLoopCommonModes];

    // Waking from sleep can land on a frame drawn before the machine went down.
    for (NSString *name in @[NSWorkspaceDidWakeNotification, NSWorkspaceScreensDidWakeNotification]) {
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                          selector:@selector(tickClock)
                                                              name:name
                                                            object:nil];
    }

    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handleKeyDown:event] ? nil : event;
    }];

    [NSApp activateIgnoringOtherApps:YES];
    [NSCursor setHiddenUntilMouseMoves:YES];
}

- (void)tickClock {
    for (WKWebView *webView in self.webViews) {
        [webView evaluateJavaScript:@"typeof updateClock === 'function' && updateClock()"
                  completionHandler:nil];
    }
    [self logPhraseOncePerMinute];
}

// Diagnostic for a report of the clock reading ten minutes behind the system, which has
// not reproduced. Recording what the page actually says, once a minute, separates a page
// that computed the wrong time from a correct page whose last frame is stuck on screen:
//
//   log show --last 12h --predicate 'eventMessage CONTAINS "GridClock phrase"' --info
- (void)logPhraseOncePerMinute {
    NSDateComponents *now = [NSCalendar.currentCalendar componentsInTimeZone:NSTimeZone.localTimeZone
                                                                    fromDate:NSDate.date];
    if (now.minute == self.lastLoggedMinute) return;
    self.lastLoggedMinute = now.minute;

    WKWebView *webView = self.webViews.firstObject;
    if (!webView) return;

    NSString *read =
        @"Array.prototype.slice.call(document.querySelectorAll('glyph'))"
         ".filter(function(g){return g.closest('.on')})"
         ".map(function(g){return g.textContent}).join('')";
    NSInteger hour = now.hour, minute = now.minute;
    [webView evaluateJavaScript:read completionHandler:^(id phrase, NSError *error) {
        os_log(OS_LOG_DEFAULT, "GridClock phrase %{public}02ld:%{public}02ld %{public}s",
               (long)hour, (long)minute,
               [([phrase isKindOfClass:NSString.class] ? phrase : @"<none>") UTF8String]);
    }];
}

- (void)buildWindows {
    for (NSWindow *window in self.windows) [window close];
    [self.windows removeAllObjects];
    [self.webViews removeAllObjects];

    NSURL *indexURL = [NSBundle.mainBundle URLForResource:@"index"
                                            withExtension:@"html"
                                             subdirectory:@"Webview"];
    if (!indexURL) {
        NSLog(@"Grid Clock: Webview/index.html missing from the app bundle");
        [NSApp terminate:nil];
        return;
    }

    for (NSScreen *screen in NSScreen.screens) {
        NSRect frame = screen.frame;

        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        configuration.suppressesIncrementalRendering = YES;

        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))
                                                configuration:configuration];
        webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        webView.navigationDelegate = self;
        if (@available(macOS 12.0, *)) webView.underPageBackgroundColor = NSColor.blackColor;
        [webView loadFileURL:indexURL allowingReadAccessToURL:indexURL.URLByDeletingLastPathComponent];

        ClockWindow *window = [[ClockWindow alloc] initWithContentRect:frame
                                                            styleMask:NSWindowStyleMaskBorderless
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO
                                                               screen:screen];
        window.contentView = webView;
        window.backgroundColor = NSColor.blackColor;
        window.opaque = YES;
        window.level = NSScreenSaverWindowLevel;
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorStationary |
                                    NSWindowCollectionBehaviorIgnoresCycle |
                                    NSWindowCollectionBehaviorFullScreenNone;
        window.releasedWhenClosed = NO;
        [window setFrame:frame display:YES];
        [window makeKeyAndOrderFront:nil];

        [self.windows addObject:window];
        [self.webViews addObject:webView];
    }
}

#pragma mark Input

- (BOOL)handleKeyDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) return NO; // let cmd-Q through

    switch (event.keyCode) {
        case 53: // esc
            [NSApp terminate:nil];
            return YES;
        case 126: // up
            [self setBrightness:self.brightness + kBrightnessStep];
            [self showHint:[NSString stringWithFormat:@"Brightness %ld%%", (long)self.brightness]];
            return YES;
        case 125: // down
            [self setBrightness:self.brightness - kBrightnessStep];
            [self showHint:[NSString stringWithFormat:@"Brightness %ld%%", (long)self.brightness]];
            return YES;
        default:
            return NO;
    }
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self.tick invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    if (self.displayAwakeActivity) [NSProcessInfo.processInfo endActivity:self.displayAwakeActivity];
    if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor];
    [NSCursor unhide];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self applyBrightnessTo:webView];
    [self showHint:@"esc to quit  ·  ↑ ↓ brightness"];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"Grid Clock: load failed: %@", error);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [webView reload];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
