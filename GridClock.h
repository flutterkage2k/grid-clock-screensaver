#import <ScreenSaver/ScreenSaver.h>
#import <WebKit/WebKit.h>

@interface GridClock : ScreenSaverView <WKNavigationDelegate>

@property (nonatomic, strong) IBOutlet NSWindow *configSheet;
@property (nonatomic, weak) IBOutlet NSPopUpButton *screenDisplayOption;

@end
