#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;
static BOOL gIcon110FolderTransitionActive = NO;

static UIImage *Icon110ShadowImage(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = @"/Library/Application Support/Icon110/Icon110Shadow@3x.png";
        image = [UIImage imageWithContentsOfFile:path];
    });
    return image;
}

typedef void (^Icon110Completion)(void);

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) NSString *location;
@property (nonatomic, strong) CALayer *icon110ShadowLayer;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
- (void)_icon110ApplyShadow;
@end

%hook SBIconView

%property (nonatomic, strong) CALayer *icon110ShadowLayer;

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
    if (!icon ||
        [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ||
        [icon isKindOfClass:NSClassFromString(@"SBHLibraryPodCategoryIcon")]) {
        self.icon110ShadowLayer.hidden = YES;
        return;
    }

    UIView *container = self.contentContainerView;
    if (!container) {
        return;
    }

    CALayer *shadowLayer = self.icon110ShadowLayer;
    if (!shadowLayer) {
        UIImage *image = Icon110ShadowImage();
        if (!image) {
            return;
        }

        shadowLayer = [CALayer layer];
        shadowLayer.contents = (__bridge id)image.CGImage;
        shadowLayer.contentsScale = image.scale;
        shadowLayer.contentsGravity = kCAGravityResizeAspect;
        shadowLayer.bounds = (CGRect){CGPointZero, image.size};
        self.icon110ShadowLayer = shadowLayer;
        [container.layer insertSublayer:shadowLayer atIndex:0];
    } else if (shadowLayer.superlayer != container.layer) {
        [shadowLayer removeFromSuperlayer];
        [container.layer insertSublayer:shadowLayer atIndex:0];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    container.layer.masksToBounds = NO;
    shadowLayer.hidden = NO;
    shadowLayer.position = CGPointMake(CGRectGetMidX(container.bounds),
                                       CGRectGetMidY(container.bounds));
    [CATransaction commit];
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
