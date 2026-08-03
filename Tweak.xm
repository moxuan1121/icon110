#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
@end

%hook SBIconView

// SpringBoard reads this value when it creates the folder transition. Report
// the same scale that is actually visible so the transition has no correction
// step at the end.
- (CGFloat)iconContentScale {
    if ([self isFolderIcon]) {
        return kIconScale;
    }
    return %orig;
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

