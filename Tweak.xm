#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;
static BOOL gIcon110FolderTransitionActive = NO;

static UIImage *Icon110ShadowImage(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGSize size = CGSizeMake(128.0, 128.0);
        // The transparent centre is slightly larger than the unscaled icon.
        // This prevents any dark pixels touching the icon during snapshots.
        CGRect iconRect = CGRectMake(32.0, 30.0, 64.0, 64.0);
        UIGraphicsBeginImageContextWithOptions(size, NO, 3.0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:iconRect
                                                        cornerRadius:15.0];

        CGContextSaveGState(context);
        // A mostly downward shadow like the reference package. Keeping the
        // blur smaller than the vertical offset avoids a dark top outline.
        CGContextSetShadowWithColor(context, CGSizeMake(0.0, 7.0), 5.0,
                                    [UIColor colorWithWhite:0.0 alpha:0.36].CGColor);
        [UIColor.blackColor setFill];
        [path fill];
        CGContextRestoreGState(context);

        CGContextSetBlendMode(context, kCGBlendModeClear);
        [path fill];
        // Keep only the shadow below the icon. The plugin contributes no
        // pixels over the icon artwork or along its top and upper sides.
        CGContextClearRect(context, CGRectMake(0.0, 0.0, size.width,
                                               CGRectGetMaxY(iconRect)));
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return image;
}

typedef void (^Icon110Completion)(void);

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) NSString *location;
@property (nonatomic, strong) CALayer *icon110ShadowLayer;
@property (nonatomic, assign) BOOL icon110ShadowSuppressed;
@property (nonatomic, assign) NSInteger icon110ShadowGeneration;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (CGFloat)iconImageCornerRadius;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
- (void)_icon110ApplyShadow;
- (void)_icon110SuppressShadowForDuration:(NSTimeInterval)duration;
@end

%hook SBIconView

%property (nonatomic, strong) CALayer *icon110ShadowLayer;
%property (nonatomic, assign) BOOL icon110ShadowSuppressed;
%property (nonatomic, assign) NSInteger icon110ShadowGeneration;

// Folder transitions consult iconContentScale for both the collapsed folder
// icon and its expanded contents. Expanded icons report 110% only while an
// actual folder push/pop is active; app-to-folder returns stay at the system
// value and therefore do not compound the content-container scale.
- (CGFloat)iconContentScale {
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return %orig;
    }

    BOOL isInsideFolder = [self.location containsString:@"SBIconLocationFolder"];
    if ([self isFolderIcon] || (gIcon110FolderTransitionActive && isInsideFolder)) {
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
    [self _icon110ApplyShadow];
}

- (void)layoutSubviews {
    %orig;
    [self _icon110ApplyShadow];
}

- (void)setTransform:(CGAffineTransform)transform {
    NSTimeInterval duration = [UIView inheritedAnimationDuration];
    if (duration > 0.0) {
        [self _icon110SuppressShadowForDuration:duration];
    }
    %orig(transform);
}

- (void)setBounds:(CGRect)bounds {
    NSTimeInterval duration = [UIView inheritedAnimationDuration];
    if (duration > 0.0) {
        [self _icon110SuppressShadowForDuration:duration];
    }
    %orig(bounds);
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

%new
- (void)_icon110ApplyShadow {
    id icon = self.icon;
    if (!icon || [self isFolderIcon] ||
        [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ||
        [icon isKindOfClass:NSClassFromString(@"SBHLibraryPodCategoryIcon")]) {
        self.icon110ShadowLayer.hidden = YES;
        return;
    }

    if (self.icon110ShadowSuppressed) {
        self.icon110ShadowLayer.hidden = YES;
        return;
    }

    UIView *container = self.contentContainerView;
    if (!container) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Clear the realtime Core Animation shadow used by 1.1.1/1.1.2. A static
    // bitmap shadow does not get recomposited during SpringBoard transitions.
    container.layer.masksToBounds = NO;
    container.layer.shadowOpacity = 0.0;
    container.layer.shadowPath = nil;

    CALayer *shadowLayer = self.icon110ShadowLayer;
    if (!shadowLayer) {
        UIImage *shadowImage = Icon110ShadowImage();
        shadowLayer = [CALayer layer];
        shadowLayer.contents = (__bridge id)shadowImage.CGImage;
        shadowLayer.contentsScale = shadowImage.scale;
        shadowLayer.contentsGravity = kCAGravityResizeAspect;
        shadowLayer.bounds = (CGRect){CGPointZero, shadowImage.size};
        shadowLayer.zPosition = -1000.0;
        self.icon110ShadowLayer = shadowLayer;
        [container.layer insertSublayer:shadowLayer atIndex:0];
    } else if (shadowLayer.superlayer != container.layer) {
        [shadowLayer removeFromSuperlayer];
        [container.layer insertSublayer:shadowLayer atIndex:0];
    }

    shadowLayer.zPosition = -1000.0;
    shadowLayer.hidden = NO;
    shadowLayer.position = CGPointMake(CGRectGetMidX(container.bounds),
                                       CGRectGetMidY(container.bounds));
    [CATransaction commit];
}

%new
- (void)_icon110SuppressShadowForDuration:(NSTimeInterval)duration {
    self.icon110ShadowSuppressed = YES;
    self.icon110ShadowLayer.hidden = YES;
    NSInteger generation = self.icon110ShadowGeneration + 1;
    self.icon110ShadowGeneration = generation;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)((duration + 0.03) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.icon110ShadowGeneration != generation) {
            return;
        }
        self.icon110ShadowSuppressed = NO;
        [self _icon110ApplyShadow];
    });
}

%end

@interface SBFolderController : UIViewController
@end

%hook SBFolderController

- (void)pushFolderIcon:(id)folderIcon
              location:(id)location
              animated:(BOOL)animated
            completion:(Icon110Completion)completion {
    gIcon110FolderTransitionActive = YES;
    Icon110Completion wrappedCompletion = ^{
        gIcon110FolderTransitionActive = NO;
        if (completion) completion();
    };
    %orig(folderIcon, location, animated, wrappedCompletion);
}

- (void)popFolderAnimated:(BOOL)animated
               completion:(Icon110Completion)completion {
    gIcon110FolderTransitionActive = YES;
    Icon110Completion wrappedCompletion = ^{
        gIcon110FolderTransitionActive = NO;
        if (completion) completion();
    };
    %orig(animated, wrappedCompletion);
}

%end

%hook SBIconListPageControl

- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(0.0);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

%end
