#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;

@interface SBIconImageView : UIView
- (void)_icon110ApplyScale;
@end

%hook SBIconImageView

- (void)didMoveToWindow {
    %orig;
    [self _icon110ApplyScale];
}

- (void)layoutSubviews {
    %orig;
    [self _icon110ApplyScale];
}

%new
- (void)_icon110ApplyScale {
    CATransform3D transform = self.layer.sublayerTransform;
    if (fabs(transform.m11 - kIconScale) < 0.001 &&
        fabs(transform.m22 - kIconScale) < 0.001) {
        return;
    }

    // Scale only the icon image contents. The SBIconImageView's own transform
    // remains untouched so SpringBoard can animate folders without a second
    // container/background scale correction at the end of the transition.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.sublayerTransform = CATransform3DMakeScale(kIconScale, kIconScale, 1.0);
    [CATransaction commit];
}

%end

