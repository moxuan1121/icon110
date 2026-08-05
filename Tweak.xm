#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static const CGFloat kIconScale = 1.10;
static BOOL gIcon110FolderTransitionActive = NO;

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
    if ([iconClassName containsString:@"Widget"] ||
        [location containsString:@"Widget"] ||
        [location containsString:@"Today"]) {
        return NO;
    }

    // Widget icon views can report a leaf icon and no useful location on the
    // Today page. Exclude them by their large bounds and widget host ancestry.
    if (CGRectGetWidth(iconView.bounds) > 100.0 ||
        CGRectGetHeight(iconView.bounds) > 100.0) {
        return NO;
    }
    UIView *ancestor = iconView.superview;
    for (NSUInteger depth = 0; ancestor && depth < 12; depth++, ancestor = ancestor.superview) {
        NSString *ancestorClassName = NSStringFromClass([ancestor class]);
        if ([ancestorClassName containsString:@"Widget"] ||
            [ancestorClassName containsString:@"Today"]) {
            return NO;
        }
    }
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

static UITargetedPreview *Icon110AdjustedPreview(UITargetedPreview *preview,
                                                  UIContextMenuInteraction *interaction) {
    SBIconView *iconView = Icon110IconViewForInteraction(interaction);
    if (!Icon110ShouldScaleIconView(iconView)) {
        return preview;
    }
    if ([iconView isFolderIcon]) {
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
    NSString *className = NSStringFromClass([delegate class]);
    Icon110PreviewIMP original = (Icon110PreviewIMP)
        [gIcon110OriginalHighlightPreviewIMPs[className] pointerValue];
    UITargetedPreview *preview = original
        ? original(delegate, selector, interaction, configuration)
        : nil;
    return Icon110AdjustedPreview(preview, interaction);
}

static UITargetedPreview *Icon110PreviewForDismissal(id delegate,
                                                      SEL selector,
                                                      UIContextMenuInteraction *interaction,
                                                      UIContextMenuConfiguration *configuration) {
    Icon110PrepareContextMenuHookStorage();
    NSString *className = NSStringFromClass([delegate class]);
    Icon110PreviewIMP original = (Icon110PreviewIMP)
        [gIcon110OriginalDismissPreviewIMPs[className] pointerValue];
    UITargetedPreview *preview = original
        ? original(delegate, selector, interaction, configuration)
        : nil;
    return Icon110AdjustedPreview(preview, interaction);
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
    if (original) {
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
    if ([self isFolderIcon] || (gIcon110FolderTransitionActive && isInsideFolder)) {
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

    if (!Icon110ShouldScaleIconView(self)) {
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
