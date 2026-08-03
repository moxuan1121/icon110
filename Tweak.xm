#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) NSString *location;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
@end

%hook SBIconView

// Folder transitions consult iconContentScale when handing views between the
// collapsed folder icon and the expanded folder list. Keep both endpoints at
// 110%, while leaving ordinary Home Screen app transitions completely stock.
- (CGFloat)iconContentScale {
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return %orig;
    }

    BOOL isInsideFolder = [self.location containsString:@"SBIconLocationFolder"];
    if ([self isFolderIcon] || isInsideFolder) {
        return kIconScale;
    }

    return %orig;
}

// Remove application and folder labels without a settings dependency.
- (void)setAllowsLabelArea:(BOOL)allowsLabelArea {
    %orig(NO);
}

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
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return;
    }

    UIView *container = self.contentContainerView;
    if (!container) {
        return;
    }

    CATransform3D transform = container.layer.sublayerTransform;
    if (fabs(transform.m11 - kIconScale) < 0.001 &&
        fabs(transform.m22 - kIconScale) < 0.001) {
        return;
    }

    // SpringBoard animates the outer SBIconView for app and folder
    // transitions. Scaling only this inner content layer keeps the native
    // transition model untouched and prevents a 110% -> 100% handoff.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    container.layer.sublayerTransform = CATransform3DMakeScale(kIconScale, kIconScale, 1.0);
    [CATransaction commit];
}

%end
