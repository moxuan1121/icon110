#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
@end

%hook SBIconView

// SpringBoard reads this value at both ends of a folder transition. Every
// non-widget icon must report the same visible scale; otherwise icons inside
// the folder are handed back to the desktop with a temporary 100% endpoint.
- (CGFloat)iconContentScale {
    CGFloat systemScale = %orig;
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return systemScale;
    }

    // Preserve SpringBoard's live app-launch/app-close interpolation and add
    // the tweak scale on top. Returning a fixed 1.10 here would flatten the
    // final part of the return-to-home animation and cause a visible hitch.
    return systemScale * kIconScale;
}

// Remove application/folder labels without loading a preferences bundle.
- (void)setAllowsLabelArea:(BOOL)allowsLabelArea {
    %orig(NO);
}

- (void)_updateIconImageViewAnimated:(BOOL)animated {
    %orig(animated);
    [self _icon110ApplyScale];
}

- (void)setIconContentScale:(CGFloat)scale {
    %orig(scale);
    [self _icon110ApplyScale];
}

- (void)didMoveToSuperview {
    %orig;
    [self _icon110ApplyScale];
}

%new
- (void)_icon110ApplyScale {
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return;
    }

    CATransform3D transform = self.layer.sublayerTransform;
    if (fabs(transform.m11 - kIconScale) < 0.001 &&
        fabs(transform.m22 - kIconScale) < 0.001) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.sublayerTransform = CATransform3DMakeScale(kIconScale, kIconScale, 1.0);
    [CATransaction commit];
}

%end
