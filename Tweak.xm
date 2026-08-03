#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
- (void)_icon110ApplyScale;
@end

%hook SBIconView

- (void)_updateIconImageViewAnimated:(BOOL)animated {
    %orig(animated);
    [self _icon110ApplyScale];
}

- (void)didMoveToSuperview {
    %orig;
    [self _icon110ApplyScale];
}

%new
- (void)_icon110ApplyScale {
    // Keep widgets at their system size; only enlarge normal app/folder icons.
    if ([self.icon isKindOfClass:objc_getClass("SBWidgetIcon")]) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.layer.sublayerTransform = CATransform3DIdentity;
        [CATransaction commit];
        return;
    }

    CATransform3D transform = self.layer.sublayerTransform;
    if (fabs(transform.m11 - kIconScale) < 0.001 &&
        fabs(transform.m22 - kIconScale) < 0.001) {
        return;
    }

    // Do not create a second implicit Core Animation transition. SpringBoard's
    // folder controller animates the surrounding icon views itself.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.sublayerTransform = CATransform3DMakeScale(kIconScale, kIconScale, 1.0);
    [CATransaction commit];
}

%end
