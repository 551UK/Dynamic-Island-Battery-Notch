// Island Battery Notch v0.2.3 - rootless SpringBoard overlay, iOS 16.3
// Target: iPhone 14 Pro Max (iPhone15,3).
// Two mirrored halves each lose 1% length on every reported 1% battery drop.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/utsname.h>
#import <string.h>
#import <objc/runtime.h>
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
// The iPhone 14 Pro Max alignment is fixed; only stroke thickness is adjustable.
static const CGFloat IBNWidth = 126.0;
static const CGFloat IBNHeight = 37.33;
static const CGFloat IBNTop = 11.0;
static CGFloat IBNThickness = 2.5;
static NSString *IBNFixedHex = @"#30D158";
static NSString *IBNChargingHex = @"#00D7FF"; // Custom charging colour (default cyan)

// iOS draws the real Dynamic Island in an elevated system window. The original
// auxiliary SpringBoard window can end up BEHIND foreground applications, so
// paint in the existing system-aperture window when one is visible.
static NSHashTable *IBNApertureViews = nil; // weak references
static char IBNApertureLayersKey;
static BOOL IBNHasActiveSystemAperture = NO;
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
    value = IBNRead(@"thickness");
    IBNThickness = IBNClamp(value ? [value doubleValue] : 2.5, 0.5, 8);
    value = IBNRead(@"fixedColor");
    IBNFixedHex = [value isKindOfClass:NSString.class] ? [value copy] : @"#30D158";
    value = IBNRead(@"chargingColor");
    IBNChargingHex = [value isKindOfClass:NSString.class] ? [value copy] : @"#00D7FF";
}
static UIColor *IBNColorFromHex(NSString *value, UIColor *fallback) {
    NSString *hex = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return fallback;
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                           green:((rgb >> 8) & 255) / 255.0
                            blue:(rgb & 255) / 255.0 alpha:1];
}
static UIColor *IBNColorForPercent(NSInteger percent) {
    // While connected to power, charging colour always overrides percentage and manual/auto modes.
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    if (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull)
        return IBNColorFromHex(IBNChargingHex, UIColor.cyanColor);
    if (!IBNAutomaticColor) return IBNColorFromHex(IBNFixedHex, UIColor.systemGreenColor);
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
// Draw OUTSIDE the physical cutout, not into it: screenshot pixels inside
// the hardware pill can show up in captures but cannot be seen on the panel.
// Our path is centred t/2 outside the nominal aperture boundary, so the
// innermost edge of the stroke stays at the original measured Island edge.
static CGRect IBNOutwardStrokeRect(CGRect rect) {
    return CGRectInset(rect, -IBNThickness / 2.0, -IBNThickness / 2.0);
}
static CGRect IBNNativeRect(UIWindow *window) {
    CGRect bounds = window.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    // Some system-aperture windows are full-screen, others just Island-sized.
    if (w >= 300 && h >= 300) {
        CGFloat portraitWidth = MIN(w, h), portraitHeight = MAX(w, h);
        CGRect r = CGRectMake((portraitWidth - IBNWidth) / 2, IBNTop, IBNWidth, IBNHeight);
        if (w > h) {
            UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
            if (orientation == UIInterfaceOrientationLandscapeRight) {
                return CGRectMake(portraitHeight - CGRectGetMaxY(r),
                                  CGRectGetMinX(r), r.size.height, r.size.width);
            }
            return CGRectMake(CGRectGetMinY(r),
                              portraitWidth - CGRectGetMaxX(r), r.size.height, r.size.width);
        }
        return r;
    }
    if (w >= 100 && h >= 25 && h < 130) {
        return CGRectMake((w - IBNWidth)/2, (h - IBNHeight)/2,
                          IBNWidth, IBNHeight);
    }
    return CGRectNull;
}
static BOOL IBNVisibleAperture(UIView *aperture) {
    if (!aperture.window || aperture.window.hidden || aperture.window.alpha <= 0.01) return NO;
    for (UIView *view = aperture; view && view != aperture.window; view = view.superview) {
        if (view.hidden || view.alpha <= 0.01) return NO;
    }
    return YES;
}
static void IBNRegisterAperture(SBSystemApertureContainerView *aperture) {
    if (!aperture) return;
    if (!IBNApertureViews) IBNApertureViews = [NSHashTable weakObjectsHashTable];
    [IBNApertureViews addObject:aperture];
}
static BOOL IBNRenderSystemAperture(void) {
    BOOL anyVisible = NO;
    NSMutableSet *seenWindows = [NSMutableSet set];
    for (SBSystemApertureContainerView *aperture in [IBNApertureViews allObjects]) {
        UIWindow *window = aperture.window;
        if (!window || window == IBNWindow) continue;
        NSArray<CAShapeLayer *> *pair = objc_getAssociatedObject(window, &IBNApertureLayersKey);
        BOOL visible = IBNVisibleAperture(aperture);
        CGRect rect = IBNNativeRect(window);
        if (CGRectIsNull(rect)) visible = NO;
        if (!visible || !IBNEnabled || UIDevice.currentDevice.batteryLevel < 0) {
            for (CAShapeLayer *layer in pair) layer.hidden = YES;
            continue;
        }
        if ([seenWindows containsObject:window]) continue;
        [seenWindows addObject:window];
        anyVisible = YES;
        if (!pair) {
            CAShapeLayer *left = [CAShapeLayer layer], *right = [CAShapeLayer layer];
            for (CAShapeLayer *layer in @[left, right]) {
                layer.fillColor = UIColor.clearColor.CGColor;
                layer.lineCap = kCALineCapButt;
                layer.lineJoin = kCALineJoinRound;
                layer.contentsScale = UIScreen.mainScreen.scale;
                layer.actions = @{@"path":NSNull.null,@"strokeStart":NSNull.null,
                                  @"strokeEnd":NSNull.null,@"strokeColor":NSNull.null,
                                  @"lineWidth":NSNull.null,@"hidden":NSNull.null};
                [window.layer addSublayer:layer];
            }
            pair = @[left, right];
            objc_setAssociatedObject(window, &IBNApertureLayersKey, pair, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // Window-level layers aren't constrained by the capsule view's mask.
        NSInteger percent = (NSInteger)lround(IBNClamp(UIDevice.currentDevice.batteryLevel, 0, 1)*100);
        CGFloat trim = (1.0 - (CGFloat)percent / 100.0)/2.0;
        UIColor *color = IBNColorForPercent(percent);
        CGRect outwardRect = IBNOutwardStrokeRect(rect);
        CGPathRef lp = IBNHalfPath(outwardRect, YES);
        CGPathRef rp = IBNHalfPath(outwardRect, NO);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (NSUInteger i = 0; i < 2; i++) {
            CAShapeLayer *layer = pair[i];
            layer.path = i == 0 ? lp : rp;
            layer.strokeColor = color.CGColor;
            layer.lineWidth = IBNThickness;
            layer.strokeStart = trim;
            layer.strokeEnd = 1.0 - trim;
            layer.hidden = (percent == 0);
            // A later inserted native subview must not cover our arcs.
            if (layer.superlayer == window.layer && window.layer.sublayers.lastObject != layer) {
                [layer removeFromSuperlayer];
                [window.layer addSublayer:layer];
            }
        }
        [CATransaction commit];
        CGPathRelease(lp);
        CGPathRelease(rp);
    }
    return anyVisible;
}

static void IBNRefresh(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ IBNRefresh(); });
        return;
    }
    IBNEnsureWindow();
    // The native aperture window is composited above foreground applications.
    IBNHasActiveSystemAperture = IBNRenderSystemAperture();
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
    if (!geomChanged && !colorChanged && IBNLastPercent == percent &&
        IBNLeft.hidden == (IBNHasActiveSystemAperture || percent == 0)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (geomChanged) {
        CGRect outwardRect = IBNOutwardStrokeRect(rect);
        CGPathRef lp = IBNHalfPath(outwardRect, YES);
        CGPathRef rp = IBNHalfPath(outwardRect, NO);
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
    IBNLeft.hidden = IBNHasActiveSystemAperture || percent == 0;
    IBNRight.hidden = IBNHasActiveSystemAperture || percent == 0;
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
    IBNRegisterAperture(self);
    IBNRefresh();
}
- (void)layoutSubviews {
    %orig;
    IBNRegisterAperture(self);
    if (self.window) IBNRefresh();
}
%end
%ctor {
    @autoreleasepool {
        struct utsname info;
        memset(&info, 0, sizeof(info));
        if (uname(&info) != 0 || strcmp(info.machine, "iPhone15,3") != 0) return;
        IBNLoadPreferences();
        IBNApertureViews = [NSHashTable weakObjectsHashTable];
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
