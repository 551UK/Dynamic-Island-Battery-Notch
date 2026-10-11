#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Follow the system capsule during live activities. CGRectNull uses the
// known-good resting/Lock Screen fallback.
CGRect IBNGeometryExpandedRect(UIView *aperture, UIWindow *window);
void IBNGeometryConfigure(dispatch_block_t refresh);
void IBNGeometryApertureDidLayout(UIView *aperture);

#ifdef __cplusplus
}
#endif
