// Island Battery Notch v0.2.0 - rootless SpringBoard overlay, iOS 16.3
// Target: iPhone 14 Pro Max (iPhone15,3).
// Two mirrored halves each lose 1% length on every reported 1% battery drop.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/utsname.h>
#import <string.h>
#import <math.h>

static void IBNRefresh(void);

@interface SpringBoard : UIApplication
@end
@interface SBSystemApertureContainerView : UIView
@end

@interface IBNOverlayWindow : UIWindow
@end
@implementation IBNOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)_canBecomeKeyWindow { return NO; }
- (BOOL)_canAffectStatusBarAppearance { return NO; }
+ (BOOL)_isSecure { return YES; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

@interface IBNOverlayController : UIViewController
@end
@implementation IBNOverlayController
- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    view.userInteractionEnabled = NO;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = view;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    IBNRefresh();
}
- (BOOL)_canAffectStatusBarAppearance { return NO; }
@end

static NSString *const IBNDomain = @"com.551.islandbatterynotch";
static NSString *const IBNNotify = @"com.551.islandbatterynotch/preferences.changed";
static BOOL IBNEnabled = YES;
static BOOL IBNAutomaticColor = YES;
static CGFloat IBNWidth = 126.0;
static CGFloat IBNHeight = 37.33;
static CGFloat IBNTop = 11.0;
static CGFloat IBNThickness = 2.5;
static NSString *IBNFixedHex = @"#30D158";

static IBNOverlayWindow *IBNWindow = nil;
static IBNOverlayController *IBNController = nil;
static CAShapeLayer *IBNLeft = nil;
static CAShapeLayer *IBNRight = nil;
static BOOL IBNNeedsFullRedraw = YES;
static NSInteger IBNLastPercent = -1;
static CGRect IBNLastRect = {{0,0},{0,0}};
static CGSize IBNLastBounds = {0,0};
static CGFloat IBNLastThickness = -1;
static CGColorRef IBNLastColor = NULL;

static id IBNRead(NSString *key) {
    CFPropertyListRef p = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)IBNDomain);
    return p ? CFBridgingRelease(p) : nil;
}
static CGFloat IBNClamp(CGFloat value, CGFloat lo, CGFloat hi) {
    return MIN(hi, MAX(lo, value));
}
static void IBNLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    id value = IBNRead(@"enabled");
    IBNEnabled = value ? [value boolValue] : YES;
    value = IBNRead(@"autoColor");
    IBNAutomaticColor = value ? [value boolValue] : YES;
    value = IBNRead(@"width");
    IBNWidth = IBNClamp(value ? [value doubleValue] : 126, 110, 150);
    value = IBNRead(@"height");
    IBNHeight = IBNClamp(value ? [value doubleValue] : 37.33, 30, 50);
    value = IBNRead(@"offsetY");
    IBNTop = IBNClamp(value ? [value doubleValue] : 11, 0, 30);
    value = IBNRead(@"thickness");
    IBNThickness = IBNClamp(value ? [value doubleValue] : 2.5, 0.5, 8);
    value = IBNRead(@"fixedColor");
    IBNFixedHex = [value isKindOfClass:NSString.class] ? [value copy] : @"#30D158";
}
static UIColor *IBNManualColor(void) {
    NSString *hex = [IBNFixedHex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return UIColor.systemGreenColor;
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return UIColor.systemGreenColor;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                           green:((rgb >> 8) & 255) / 255.0
                            blue:(rgb & 255) / 255.0 alpha:1];
}
static UIColor *IBNColorForPercent(NSInteger percent) {
    if (!IBNAutomaticColor) return IBNManualColor();
    if (percent <= 20) return [UIColor colorWithRed:1 green:69.0 / 255 blue:58.0 / 255 alpha:1];
    if (percent <= 60) return [UIColor colorWithRed:1 green:214.0 / 255 blue:10.0 / 255 alpha:1];
    return [UIColor colorWithRed:48.0 / 255 green:209.0 / 255 blue:88.0 / 255 alpha:1];
}
// A complete half traces from the top centre around an outside semicircle to the bottom centre.
static CGPathRef IBNHalfPath(CGRect r, BOOL left) {
    const CGFloat k = 0.5522847498307936;
    CGFloat radius = CGRectGetHeight(r) / 2.0;
    CGFloat centreX = CGRectGetMidX(r);
    CGFloat centreY = CGRectGetMidY(r);
    CGFloat edgeX = left ? CGRectGetMinX(r) : CGRectGetMaxX(r);
    CGFloat arcX = left ? edgeX + radius : edgeX - radius;
    CGFloat sign = left ? -1.0 : 1.0;
    CGFloat top = CGRectGetMinY(r), bottom = CGRectGetMaxY(r);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(centreX, top)];
    [p addLineToPoint:CGPointMake(arcX, top)];
    [p addCurveToPoint:CGPointMake(edgeX, centreY)
        controlPoint1:CGPointMake(arcX + sign * radius * k, top)
        controlPoint2:CGPointMake(edgeX, centreY - radius * k)];
    [p addCurveToPoint:CGPointMake(arcX, bottom)
        controlPoint1:CGPointMake(edgeX, centreY + radius * k)
        controlPoint2:CGPointMake(arcX + sign * radius * k, bottom)];
    [p addLineToPoint:CGPointMake(centreX, bottom)];
    return CGPathCreateCopy(p.CGPath);
}
static UIWindowScene *IBNMainScene(void) {
    UIWindowScene *preferred = UIApplication.sharedApplication.keyWindow.windowScene;
    if (preferred && preferred.screen == UIScreen.mainScreen) return preferred;
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.screen != UIScreen.mainScreen) continue;
        if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
        if (!fallback) fallback = ws;
    }
    return fallback;
}
static void IBNEnsureWindow(void) {
    UIWindowScene *scene = IBNMainScene();
    if (!scene) return; // SpringBoard may not have connected a scene yet.
    if (IBNWindow) {
        if (IBNWindow.windowScene != scene) {
            IBNWindow.hidden = YES;
            IBNWindow.windowScene = scene;
            IBNWindow.frame = [UIScreen mainScreen].bounds;
            IBNWindow.hidden = NO;
            IBNNeedsFullRedraw = YES;
        }
        return;
    }
    IBNWindow = [[IBNOverlayWindow alloc] initWithWindowScene:scene];
    IBNWindow.frame = UIScreen.mainScreen.bounds;
    IBNWindow.windowLevel = 10000.0;
    IBNWindow.backgroundColor = UIColor.clearColor;
    IBNWindow.opaque = NO;
    IBNWindow.userInteractionEnabled = NO;
    IBNController = [IBNOverlayController new];
    IBNWindow.rootViewController = IBNController;
    IBNLeft = [CAShapeLayer layer];
    IBNRight = [CAShapeLayer layer];
    for (CAShapeLayer *layer in @[IBNLeft, IBNRight]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.lineCap = kCALineCapButt;
        layer.lineJoin = kCALineJoinRound;
        layer.contentsScale = UIScreen.mainScreen.scale;
        layer.actions = @{ @"strokeStart": NSNull.null, @"strokeEnd": NSNull.null,
                            @"path": NSNull.null, @"strokeColor": NSNull.null,
                            @"lineWidth": NSNull.null, @"hidden": NSNull.null };
        [IBNController.view.layer addSublayer:layer];
    }
    IBNWindow.hidden = NO; // Do not steal the app's key window.
    IBNNeedsFullRedraw = YES;
}
static void IBNRefresh(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ IBNRefresh(); });
        return;
    }
    IBNEnsureWindow();
    if (!IBNWindow || !IBNLeft || !IBNRight) return;
    if (!IBNEnabled) {
        IBNLeft.hidden = YES;
        IBNRight.hidden = YES;
        return;
    }
    UIDevice *device = UIDevice.currentDevice;
    if (!device.batteryMonitoringEnabled) device.batteryMonitoringEnabled = YES;
    if (device.batteryLevel < 0) {
        IBNLeft.hidden = YES;
        IBNRight.hidden = YES;
        return;
    }
    NSInteger percent = (NSInteger)lround(IBNClamp(device.batteryLevel, 0, 1) * 100);
    CGFloat progress = (CGFloat)percent / 100.0;
    UIColor *color = IBNColorForPercent(percent);
    CGRect bounds = IBNController.view.bounds;
    if (bounds.size.width < 300 || bounds.size.height < 300) return;
    BOOL landscape = CGRectGetWidth(bounds) > CGRectGetHeight(bounds);
    CGFloat portraitWidth = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
    CGFloat portraitHeight = MAX(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
    CGRect rect = CGRectMake((portraitWidth - IBNWidth) / 2, IBNTop, IBNWidth, IBNHeight);
    BOOL geomChanged = IBNNeedsFullRedraw || !CGRectEqualToRect(rect, IBNLastRect)
        || !CGSizeEqualToSize(bounds.size, IBNLastBounds)
        || (IBNLastThickness != IBNThickness);
    BOOL colorChanged = IBNNeedsFullRedraw || !IBNLastColor || !CGColorEqualToColor(IBNLastColor, color.CGColor);
    if (!geomChanged && !colorChanged && IBNLastPercent == percent && !IBNLeft.hidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (geomChanged) {
        CGRect inner = CGRectInset(rect, IBNThickness / 2, IBNThickness / 2);
        CGPathRef lp = IBNHalfPath(inner, YES);
        CGPathRef rp = IBNHalfPath(inner, NO);
        if (landscape) {
            UIInterfaceOrientation o = IBNWindow.windowScene.interfaceOrientation;
            CGAffineTransform transform = (o == UIInterfaceOrientationLandscapeRight)
                ? CGAffineTransformMake(0, 1, -1, 0, portraitHeight, 0)
                : CGAffineTransformMake(0, -1, 1, 0, 0, portraitWidth);
            CGPathRef lpr = CGPathCreateCopyByTransformingPath(lp, &transform);
            CGPathRef rpr = CGPathCreateCopyByTransformingPath(rp, &transform);
            CGPathRelease(lp); CGPathRelease(rp);
            lp = lpr; rp = rpr;
        }
        IBNLeft.path = lp;
        IBNRight.path = rp;
        CGPathRelease(lp); CGPathRelease(rp);
        IBNLeft.lineWidth = IBNThickness;
        IBNRight.lineWidth = IBNThickness;
    }
    if (colorChanged) {
        IBNLeft.strokeColor = color.CGColor;
        IBNRight.strokeColor = color.CGColor;
        if (IBNLastColor) CGColorRelease(IBNLastColor);
        IBNLastColor = CGColorRetain(color.CGColor);
    }
    CGFloat trim = (1.0 - progress) / 2.0;
    IBNLeft.strokeStart = trim;
    IBNRight.strokeStart = trim;
    IBNLeft.strokeEnd = 1.0 - trim;
    IBNRight.strokeEnd = 1.0 - trim;
    IBNLeft.hidden = percent == 0;
    IBNRight.hidden = percent == 0;
    [CATransaction commit];
    IBNLastRect = rect;
    IBNLastBounds = bounds.size;
    IBNLastThickness = IBNThickness;
    IBNLastPercent = percent;
    IBNNeedsFullRedraw = NO;
}
static void IBNPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef info) {
    IBNLoadPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{ IBNNeedsFullRedraw = YES; IBNRefresh(); });
}
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig(application);
    dispatch_async(dispatch_get_main_queue(), ^{ IBNRefresh(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ IBNRefresh(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ IBNRefresh(); });
}
%end
%hook SBSystemApertureContainerView
- (void)didMoveToWindow {
    %orig;
    if (self.window) IBNRefresh();
}
- (void)layoutSubviews {
    %orig;
    if (self.window) IBNRefresh();
}
%end
%ctor {
    @autoreleasepool {
        struct utsname info = {0};
        if (uname(&info) != 0 || strcmp(info.machine, "iPhone15,3") != 0) return;
        IBNLoadPreferences();
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
        %init;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[ UIDeviceBatteryLevelDidChangeNotification,
                                   UIDeviceBatteryStateDidChangeNotification,
                                   UISceneDidActivateNotification,
                                   UIApplicationDidBecomeActiveNotification ]) {
            [nc addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *n) { IBNRefresh(); }];
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, IBNPrefsChanged, (__bridge CFStringRef)IBNNotify,
                                        NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
}
