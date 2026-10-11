#import "IBNGeometry.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

// Read the actual rounded system-aperture view, not its full-screen window.
static dispatch_block_t IBNGeometryRefresh = nil;
static CADisplayLink *IBNGeometryLink = nil;
static CFTimeInterval IBNGeometryLinkStarted = 0;
static CFTimeInterval IBNGeometryLinkUntil = 0;
static CGRect IBNGeometryLastCandidate = {{0,0},{0,0}};
static BOOL IBNGeometryCandidateKnown = NO;

@interface IBNGeometryFrameDriver : NSObject
- (void)tick:(CADisplayLink *)link;
@end

static BOOL IBNGeometryValid(CGRect rect, UIWindow *window) {
    if (!window || CGRectIsNull(rect) || CGRectIsInfinite(rect) || CGRectIsEmpty(rect)) return NO;
    CGFloat width = CGRectGetWidth(rect), height = CGRectGetHeight(rect);
    CGFloat winWidth = CGRectGetWidth(window.bounds);
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(width) || !isfinite(height)) return NO;
    // Full-width activities can approach the edge of the device.
    if (width < 105 || width > MIN(winWidth + 2.0, 455.0) ||
        height < 30 || height > 160 || width/height < 1.45) return NO;
    // Reject off-centre notifications and unrelated accessory frames.
    if (fabs(CGRectGetMidX(rect) - winWidth/2.0) > 27.0) return NO;
    if (CGRectGetMinX(rect) < -2.0 ||
        CGRectGetMaxX(rect) > winWidth + 2.0) return NO;
    if (CGRectGetMinY(rect) < -9.0 || CGRectGetMaxY(rect) > 200) return NO;
    return YES;
}

static CGRect IBNGeometryModelRect(UIView *aperture, UIWindow *window) {
    if (!aperture || !window || aperture.window != window) return CGRectNull;
    CGRect rect = CGRectNull;
    @try { rect = [aperture convertRect:aperture.bounds toView:window]; }
    @catch (__unused NSException *exception) { return CGRectNull; }
    return IBNGeometryValid(rect, window) ? rect : CGRectNull;
}

static CGRect IBNGeometryPresentedRect(UIView *aperture, UIWindow *window, CGRect model) {
    CALayer *presentation = aperture.layer.presentationLayer;
    CALayer *windowPresentation = window.layer.presentationLayer;
    if (!presentation || !windowPresentation) return model;
    @try {
        CGRect candidate = [presentation convertRect:presentation.bounds toLayer:windowPresentation];
        // A presentation-layer conversion can yield the wrong coordinate
        // space for secure/composited windows. Accept ONLY if close to the
        // directly measured, verified UIKit frame. Otherwise use UIKit.
        if (IBNGeometryValid(candidate, window) &&
            fabs(CGRectGetMidX(candidate) - CGRectGetMidX(model)) <= 24.0 &&
            fabs(CGRectGetMidY(candidate) - CGRectGetMidY(model)) <= 20.0 &&
            fabs(CGRectGetWidth(candidate) - CGRectGetWidth(model)) <= 75.0 &&
            fabs(CGRectGetHeight(candidate) - CGRectGetHeight(model)) <= 38.0)
            return candidate;
    } @catch (__unused NSException *exception) {}
    return model;
}

static CGRect IBNGeometryCapsuleRect(UIView *aperture, UIWindow *window) {
    if (!aperture || !window || aperture.window != window ||
        aperture.hidden || aperture.alpha < 0.05) return CGRectNull;
    NSString *name = NSStringFromClass(aperture.class);
    if (![name isEqualToString:@"SBSystemApertureContainerView"]) return CGRectNull;
    // The secure aperture window's scene-orientation flag can be stale.
    if (CGRectGetWidth(window.bounds) >= CGRectGetHeight(window.bounds))
        return CGRectNull;
    CALayer *layer = aperture.layer;
    CALayer *presentation = layer.presentationLayer ?: layer;
    CGRect model = IBNGeometryModelRect(aperture, window);
    if (CGRectIsNull(model)) return CGRectNull;
    // The observed real capsule has a corner radius of half its height.
    // Do not confuse the unrounded child/scene with the black capsule.
    CGFloat radius = MAX(layer.cornerRadius, presentation.cornerRadius);
    if (radius < 12 || radius < CGRectGetHeight(model) * 0.30)
        return CGRectNull;
    return IBNGeometryPresentedRect(aperture, window, model);
}

CGRect IBNGeometryExpandedRect(UIView *aperture, UIWindow *window) {
    CGRect rect = IBNGeometryCapsuleRect(aperture, window);
    if (CGRectIsNull(rect)) return CGRectNull;
    // Preserve the calibrated resting shape; follow larger live activities.
    if (CGRectGetWidth(rect) < 145.0 && CGRectGetHeight(rect) < 44.0)
        return CGRectNull;
    return rect;
}

@implementation IBNGeometryFrameDriver
- (void)tick:(CADisplayLink *)link {
    if (CACurrentMediaTime() >= IBNGeometryLinkUntil ||
        CACurrentMediaTime() - IBNGeometryLinkStarted >= 3.0) {
        [link invalidate];
        if (IBNGeometryLink == link) IBNGeometryLink = nil;
        return;
    }
    if (IBNGeometryRefresh) IBNGeometryRefresh();
}
@end

void IBNGeometryConfigure(dispatch_block_t refresh) {
    IBNGeometryRefresh = [refresh copy];
}

void IBNGeometryApertureDidLayout(UIView *aperture) {
    if (!aperture.window) return;
    // Trigger burst when model frame changes, before the animation catches up.
    CGRect candidate = IBNGeometryModelRect(aperture, aperture.window);
    BOOL known = !CGRectIsNull(candidate);
    BOOL changed = known != IBNGeometryCandidateKnown ||
        (known && (!IBNGeometryCandidateKnown ||
        fabs(candidate.origin.x - IBNGeometryLastCandidate.origin.x) > 0.35 ||
        fabs(candidate.origin.y - IBNGeometryLastCandidate.origin.y) > 0.35 ||
        fabs(candidate.size.width - IBNGeometryLastCandidate.size.width) > 0.35 ||
        fabs(candidate.size.height - IBNGeometryLastCandidate.size.height) > 0.35));
    if (!changed) return;
    IBNGeometryCandidateKnown = known;
    IBNGeometryLastCandidate = candidate;
    CFTimeInterval now = CACurrentMediaTime();
    IBNGeometryLinkUntil = now + 1.5;
    if (!IBNGeometryLink) {
        IBNGeometryLinkStarted = now;
        IBNGeometryFrameDriver *driver = [IBNGeometryFrameDriver new];
        IBNGeometryLink = [CADisplayLink displayLinkWithTarget:driver selector:@selector(tick:)];
        IBNGeometryLink.preferredFramesPerSecond = 30;
        [IBNGeometryLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
