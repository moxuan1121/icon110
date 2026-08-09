#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;
static NSUInteger gIcon110FolderTransitionDepth = 0;

static BOOL Icon110FolderTransitionIsActive(void) {
    return gIcon110FolderTransitionDepth > 0;
}

static void Icon110BeginFolderTransition(void) {
    gIcon110FolderTransitionDepth++;
}

static void Icon110EndFolderTransition(void) {
    if (gIcon110FolderTransitionDepth > 0) {
        gIcon110FolderTransitionDepth--;
    }
}

typedef void (^Icon110Completion)(void);
typedef UITargetedPreview *(*Icon110PreviewIMP)(id, SEL, UIContextMenuInteraction *, UIContextMenuConfiguration *);

static NSMutableDictionary<NSString *, NSValue *> *gIcon110OriginalHighlightPreviewIMPs;
static NSMutableDictionary<NSString *, NSValue *> *gIcon110OriginalDismissPreviewIMPs;
static NSMutableSet<NSString *> *gIcon110HookedContextMenuDelegateClasses;

static void Icon110PrepareContextMenuHookStorage(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gIcon110OriginalHighlightPreviewIMPs = [NSMutableDictionary dictionary];
        gIcon110OriginalDismissPreviewIMPs = [NSMutableDictionary dictionary];
        gIcon110HookedContextMenuDelegateClasses = [NSMutableSet set];
    });
}

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) NSString *location;
@property (nonatomic, assign) BOOL icon110ScaleApplied;
@property (nonatomic, strong) NSValue *icon110OriginalSublayerTransform;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
- (void)_icon110HideLabel;
@end

static void Icon110HideLabelSubviews(UIView *view, NSUInteger depth) {
    if (!view || depth > 3) return;
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass([subview class]);
        if ([className containsString:@"IconLabel"] ||
            [className containsString:@"LabelView"]) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        } else {
            Icon110HideLabelSubviews(subview, depth + 1);
        }
    }
}

static BOOL Icon110ShouldScaleIconView(SBIconView *iconView) {
    if (!iconView || !iconView.icon) return NO;
    NSString *iconClassName = NSStringFromClass([iconView.icon class]);
    NSString *location = iconView.location ?: @"";
    BOOL isWidget = [iconClassName containsString:@"Widget"] ||
                    [location containsString:@"Widget"] ||
                    CGRectGetWidth(iconView.bounds) > 100.0 ||
                    CGRectGetHeight(iconView.bounds) > 100.0;
    BOOL isTodayView = [location containsString:@"Today"];
    UIView *ancestor = iconView.superview;
    for (NSUInteger depth = 0; ancestor && depth < 12; depth++, ancestor = ancestor.superview) {
        NSString *ancestorClassName = NSStringFromClass([ancestor class]);
        isWidget = isWidget || [ancestorClassName containsString:@"Widget"];
        isTodayView = isTodayView || [ancestorClassName containsString:@"Today"];
    }

    if (isTodayView || isWidget) return NO;
    return YES;
}

static SBIconView *Icon110IconViewForInteraction(UIContextMenuInteraction *interaction) {
    UIView *candidate = interaction.view;
    Class iconViewClass = NSClassFromString(@"SBIconView");
    while (candidate && ![candidate isKindOfClass:iconViewClass]) {
        candidate = candidate.superview;
    }
    return (SBIconView *)candidate;
}

static Icon110PreviewIMP Icon110OriginalPreviewIMPForDelegate(
    id delegate,
    NSMutableDictionary<NSString *, NSValue *> *originals) {
    for (Class currentClass = [delegate class];
         currentClass;
         currentClass = class_getSuperclass(currentClass)) {
        NSValue *storedIMP = originals[NSStringFromClass(currentClass)];
        if (storedIMP) {
            return (Icon110PreviewIMP)[storedIMP pointerValue];
        }
    }
    return NULL;
}

static UITargetedPreview *Icon110AdjustedPreview(UITargetedPreview *preview,
                                                  UIContextMenuInteraction *interaction,
                                                  BOOL adjustsFolder) {
    SBIconView *iconView = Icon110IconViewForInteraction(interaction);
    if (!Icon110ShouldScaleIconView(iconView)) {
        return preview;
    }
    if ([iconView isFolderIcon] && !adjustsFolder) {
        return preview;
    }

    UIView *sourceView = preview.view ?: iconView.contentContainerView;
    UIView *container = preview.target.container ?: iconView.superview;
    if (!sourceView || !container) return preview;

    CGPoint center = preview
        ? preview.target.center
        : [container convertPoint:iconView.center fromView:iconView.superview];
    CGAffineTransform transform = preview
        ? preview.target.transform
        : CGAffineTransformIdentity;
    transform = CGAffineTransformConcat(transform,
                                        CGAffineTransformMakeScale(kIconScale, kIconScale));

    UIPreviewTarget *target = [[UIPreviewTarget alloc] initWithContainer:container
                                                                  center:center
                                                               transform:transform];
    UIPreviewParameters *parameters = preview.parameters ?: [UIPreviewParameters new];
    return [[UITargetedPreview alloc] initWithView:sourceView
                                        parameters:parameters
                                            target:target];
}

static UITargetedPreview *Icon110PreviewForHighlighting(id delegate,
                                                         SEL selector,
                                                         UIContextMenuInteraction *interaction,
                                                         UIContextMenuConfiguration *configuration) {
    Icon110PrepareContextMenuHookStorage();
    Icon110PreviewIMP original = Icon110OriginalPreviewIMPForDelegate(
        delegate, gIcon110OriginalHighlightPreviewIMPs);
    UITargetedPreview *preview = original
        ? original(delegate, selector, interaction, configuration)
        : nil;
    return Icon110AdjustedPreview(preview, interaction, NO);
}

static UITargetedPreview *Icon110PreviewForDismissal(id delegate,
                                                      SEL selector,
                                                      UIContextMenuInteraction *interaction,
                                                      UIContextMenuConfiguration *configuration) {
    Icon110PrepareContextMenuHookStorage();
    Icon110PreviewIMP original = Icon110OriginalPreviewIMPForDelegate(
        delegate, gIcon110OriginalDismissPreviewIMPs);
    UITargetedPreview *preview = original
        ? original(delegate, selector, interaction, configuration)
        : nil;
    return Icon110AdjustedPreview(preview, interaction, YES);
}

static void Icon110InstallPreviewHook(Class delegateClass,
                                      NSString *className,
                                      SEL selector,
                                      IMP replacement,
                                      NSMutableDictionary<NSString *, NSValue *> *originals) {
    Method inheritedMethod = class_getInstanceMethod(delegateClass, selector);
    const char *types = inheritedMethod ? method_getTypeEncoding(inheritedMethod) : "@@:@@";
    IMP inheritedIMP = inheritedMethod ? method_getImplementation(inheritedMethod) : NULL;

    IMP original = NULL;
    if (class_addMethod(delegateClass, selector, replacement, types)) {
        original = inheritedIMP;
    } else {
        Method method = class_getInstanceMethod(delegateClass, selector);
        original = method_setImplementation(method, replacement);
    }
    // A subclass may inherit our replacement from a previously hooked parent.
    // Do not record that replacement as its original implementation; callback
    // lookup will continue up the class hierarchy to the real original IMP.
    if (original && original != replacement) {
        originals[className] = [NSValue valueWithPointer:(const void *)original];
    }
}

static void Icon110HookContextMenuDelegate(id delegate) {
    if (!delegate) return;

    Icon110PrepareContextMenuHookStorage();
    Class delegateClass = [delegate class];
    NSString *className = NSStringFromClass(delegateClass);
    if ([gIcon110HookedContextMenuDelegateClasses containsObject:className]) return;
    [gIcon110HookedContextMenuDelegateClasses addObject:className];

    Icon110InstallPreviewHook(delegateClass, className,
        @selector(contextMenuInteraction:previewForHighlightingMenuWithConfiguration:),
        (IMP)Icon110PreviewForHighlighting, gIcon110OriginalHighlightPreviewIMPs);
    Icon110InstallPreviewHook(delegateClass, className,
        @selector(contextMenuInteraction:previewForDismissingMenuWithConfiguration:),
        (IMP)Icon110PreviewForDismissal, gIcon110OriginalDismissPreviewIMPs);
}

%hook SBIconView

%property (nonatomic, assign) BOOL icon110ScaleApplied;
%property (nonatomic, strong) NSValue *icon110OriginalSublayerTransform;

- (CGFloat)iconContentScale {
    if (!Icon110ShouldScaleIconView(self)) {
        return %orig;
    }

    BOOL isInsideFolder = [self.location containsString:@"SBIconLocationFolder"];
    if (Icon110FolderTransitionIsActive() && ([self isFolderIcon] || isInsideFolder)) {
        return kIconScale;
    }

    return %orig;
}

- (void)setAllowsLabelArea:(BOOL)allowsLabelArea {
    %orig(NO);
    [self _icon110HideLabel];
}

- (void)_updateIconImageViewAnimated:(BOOL)animated {
    %orig(animated);
    [self _icon110ApplyScale];
    [self _icon110HideLabel];
}

- (void)didMoveToSuperview {
    %orig;
    [self _icon110ApplyScale];
    [self _icon110HideLabel];
}

- (void)layoutSubviews {
    %orig;
    [self _icon110ApplyScale];
    [self _icon110HideLabel];
}

%new
- (void)_icon110ApplyScale {
    UIView *container = self.contentContainerView;
    if (!container) return;

    // Static icons, including folder icons, use one sublayer scale. Folder
    // context-menu previews are excluded separately, so no second 1.10 is
    // compounded during highlighting or dismissal.
    BOOL shouldUseSublayerScale = Icon110ShouldScaleIconView(self);
    if (!shouldUseSublayerScale) {
        if (self.icon110ScaleApplied) {
            CATransform3D originalTransform = self.icon110OriginalSublayerTransform
                ? [self.icon110OriginalSublayerTransform CATransform3DValue]
                : CATransform3DIdentity;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            container.layer.sublayerTransform = originalTransform;
            [CATransaction commit];
            self.icon110ScaleApplied = NO;
            self.icon110OriginalSublayerTransform = nil;
        }
        return;
    }

    CATransform3D transform = container.layer.sublayerTransform;
    if (fabs(transform.m11 - kIconScale) < 0.001 &&
        fabs(transform.m22 - kIconScale) < 0.001) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!self.icon110ScaleApplied) {
        self.icon110OriginalSublayerTransform = [NSValue valueWithCATransform3D:transform];
    }
    container.layer.sublayerTransform = CATransform3DMakeScale(kIconScale, kIconScale, 1.0);
    [CATransaction commit];
    self.icon110ScaleApplied = YES;
}

%new
- (void)_icon110HideLabel {
    Icon110HideLabelSubviews(self, 0);
}

%end

%hook UIContextMenuInteraction

- (instancetype)initWithDelegate:(id<UIContextMenuInteractionDelegate>)delegate {
    UIContextMenuInteraction *interaction = %orig(delegate);
    Icon110HookContextMenuDelegate(delegate);
    return interaction;
}

%end

@interface SBFolderController : UIViewController
@end

%hook SBFolderController

- (void)pushFolderIcon:(id)folderIcon
              location:(id)location
              animated:(BOOL)animated
            completion:(Icon110Completion)completion {
    Icon110BeginFolderTransition();
    Icon110Completion wrappedCompletion = ^{
        Icon110EndFolderTransition();
        if (completion) completion();
    };
    %orig(folderIcon, location, animated, wrappedCompletion);
}

- (void)popFolderAnimated:(BOOL)animated
               completion:(Icon110Completion)completion {
    Icon110BeginFolderTransition();
    Icon110Completion wrappedCompletion = ^{
        Icon110EndFolderTransition();
        if (completion) completion();
    };
    %orig(animated, wrappedCompletion);
}

%end

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(CGFloat)alpha;
@end

%hook SBDockView

- (void)setBackgroundAlpha:(CGFloat)alpha {
    %orig(0.0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    [self setBackgroundAlpha:0.0];
}

%end

%hook SBFolderBackgroundView

- (void)layoutSubviews {
    %orig;
    UIView *backgroundView = (UIView *)self;
    backgroundView.hidden = YES;
    backgroundView.alpha = 0.0;
}

%end

@interface SBFolderIconImageView : UIView
@property (nonatomic, strong) UIView *icon110TransparentBackgroundView;
@end

%hook SBFolderIconImageView

%property (nonatomic, strong) UIView *icon110TransparentBackgroundView;

- (void)setBackgroundView:(id)backgroundView {
    UIView *transparentView = self.icon110TransparentBackgroundView;
    if (!transparentView) {
        transparentView = [[UIView alloc] initWithFrame:CGRectZero];
        transparentView.userInteractionEnabled = NO;
        transparentView.backgroundColor = [UIColor clearColor];
        self.icon110TransparentBackgroundView = transparentView;
    }
    // iOS 15 renders the Home Screen folder plate through this assigned view.
    // Reusing one blank view preserves the system transition handoff without
    // drawing the material behind the miniature icons.
    %orig(transparentView);
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
