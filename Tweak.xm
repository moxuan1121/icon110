#import <UIKit/UIKit.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;
static BOOL gIcon110FolderTransitionActive = NO;

typedef void (^Icon110Completion)(void);

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) NSString *location;
@property (nonatomic, assign) BOOL icon110ContextMenuDismissing;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
- (void)_icon110BeginContextMenuDismissal;
- (void)_icon110EndContextMenuDismissal;
@end

%hook SBIconView

%property (nonatomic, assign) BOOL icon110ContextMenuDismissing;

// Folder transitions consult iconContentScale for both the collapsed folder
// icon and its expanded contents. Expanded icons report 110% only while an
// actual folder push/pop is active; app-to-folder returns stay at the system
// value and therefore do not compound the content-container scale.
- (CGFloat)iconContentScale {
    if ([self.icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
        return %orig;
    }

    if (self.icon110ContextMenuDismissing) {
        return kIconScale;
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
- (void)_icon110BeginContextMenuDismissal {
    if (self.icon110ContextMenuDismissing) return;

    self.icon110ContextMenuDismissing = YES;
    UIView *container = self.contentContainerView;
    if (!container) return;

    // During dismissal SpringBoard asks iconContentScale for the temporary
    // context-menu snapshot. Let the system provide 110% and temporarily
    // remove our separate 110% layer so the two scales do not compound.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    container.layer.sublayerTransform = CATransform3DIdentity;
    [CATransaction commit];
}

%new
- (void)_icon110EndContextMenuDismissal {
    if (!self.icon110ContextMenuDismissing) return;
    self.icon110ContextMenuDismissing = NO;
    [self _icon110ApplyScale];
}

%end

%hook UIContextMenuInteraction

- (void)dismissMenu {
    UIView *candidate = self.view;
    Class iconViewClass = NSClassFromString(@"SBIconView");
    while (candidate && ![candidate isKindOfClass:iconViewClass]) {
        candidate = candidate.superview;
    }

    SBIconView *iconView = (SBIconView *)candidate;
    [iconView _icon110BeginContextMenuDismissal];
    %orig;

    if (iconView) {
        __weak SBIconView *weakIconView = iconView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakIconView _icon110EndContextMenuDismissal];
        });
    }
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
