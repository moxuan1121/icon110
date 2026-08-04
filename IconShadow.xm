#import <UIKit/UIKit.h>

#if __has_include(<roothide.h>)
#include <roothide.h>
#define ICONSHADOW_JBROOT(path) jbroot(path)
#else
#define ICONSHADOW_JBROOT(path) (path)
#endif

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) CALayer *iconShadowLayer;
- (BOOL)isFolderIcon;
- (void)_iconShadowSetup;
- (void)_iconShadowDetach;
@end

%hook SBIconView

%property (nonatomic, strong) CALayer *iconShadowLayer;

- (instancetype)initWithConfigurationOptions:(NSUInteger)options
                           listLayoutProvider:(id)layoutProvider {
    SBIconView *view = %orig(options, layoutProvider);
    [view _iconShadowSetup];
    return view;
}

- (void)setIcon:(id)icon {
    // SBIconView instances are reused by SpringBoard.  Detach the old layer
    // before the icon changes so a normal icon shadow can never survive for
    // one frame in a folder thumbnail or transition view.
    [self _iconShadowDetach];
    %orig(icon);
    [self _iconShadowSetup];
}

- (void)layoutSubviews {
    %orig;
    [self _iconShadowSetup];
    CALayer *shadow = self.iconShadowLayer;
    UIView *container = self.contentContainerView;
    if (!shadow || !container || shadow.superlayer != container.layer) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    shadow.position = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    // The content container already receives Icon110's 1.10 sublayer scale.
    // Keeping this layer at identity makes the icon and shadow share one
    // transform during app and folder transitions instead of handing off
    // between two independently animated layer trees.
    shadow.transform = CATransform3DIdentity;
    [CATransaction commit];
}

%new
- (void)_iconShadowSetup {
    id icon = self.icon;
    UIView *container = self.contentContainerView;
    if (!icon || !container || [self isFolderIcon] ||
        [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ||
        [icon isKindOfClass:NSClassFromString(@"SBHLibraryPodCategoryIcon")]) {
        [self _iconShadowDetach];
        return;
    }

    CALayer *shadow = self.iconShadowLayer;
    if (!shadow) {
        NSString *path = ICONSHADOW_JBROOT(@"/Library/Themes/iconShadow@3x.png");
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image) return;

        shadow = [CALayer layer];
        shadow.contents = (__bridge id)image.CGImage;
        shadow.contentsScale = image.scale;
        shadow.contentsGravity = kCAGravityResizeAspect;
        shadow.bounds = (CGRect){CGPointZero, image.size};
        self.iconShadowLayer = shadow;
    }

    self.layer.masksToBounds = NO;
    container.layer.masksToBounds = NO;
    if (shadow.superlayer != container.layer) {
        [shadow removeFromSuperlayer];
        [container.layer insertSublayer:shadow atIndex:0];
    }
    shadow.hidden = NO;
}

%new
- (void)_iconShadowDetach {
    CALayer *shadow = self.iconShadowLayer;
    if (!shadow) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    shadow.hidden = YES;
    [shadow removeFromSuperlayer];
    [CATransaction commit];
}

%end
