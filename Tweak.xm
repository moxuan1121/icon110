#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>
#import <roothide.h>

static const CGFloat kIconScale = 1.10;
static NSUInteger gIcon110FolderTransitionDepth = 0;
static BOOL gShadowFolderPresented = NO;
static BOOL gShadowFolderClosing = NO;
static BOOL gShadowFolderPreparing = NO;
static BOOL gShadowFolderOpenStable = NO;
static BOOL gShadowDragging = NO;
static NSUInteger gShadowFolderTransitionGeneration = 0;
static NSUInteger gShadowDragGeneration = 0;
static NSHashTable *gShadowIconViews;
static NSHashTable *gShadowImageViews;
static UIImage *gShadowImage;

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
@property (nonatomic, readonly) CGFloat effectiveIconImageAlpha;
@property (nonatomic, readonly, getter=isDragging) BOOL dragging;
@property (nonatomic, assign) BOOL icon110ScaleApplied;
@property (nonatomic, strong) NSValue *icon110OriginalSublayerTransform;
@property (nonatomic, strong) UIImageView *icon110ShadowView;
- (id)initWithConfigurationOptions:(id)options listLayoutProvider:(id)provider;
- (BOOL)isFolderIcon;
- (CGFloat)iconContentScale;
- (BOOL)shouldShowLabelAccessoryView;
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_icon110ApplyScale;
- (void)_icon110HideLabel;
- (void)_icon110SetUpShadow;
- (void)_icon110UpdateShadowLayout;
- (NSArray *)dragInteraction:(id)interaction itemsForBeginningSession:(id)session;
- (id)dragPreviewForItem:(id)item session:(id)session;
- (void)dragInteraction:(id)interaction session:(id)session didEndWithOperation:(NSUInteger)operation;
@end

@interface SBIconImageView : UIView
@property (nonatomic, strong) CALayer *icon110ShadowLayer;
@property (nonatomic, strong) NSString *icon110ShadowLocation;
- (void)setIcon:(id)icon location:(id)location animated:(BOOL)animated;
- (void)prepareForReuse;
- (void)_icon110UpdateCarrierShadow;
- (void)_icon110ClearCarrierShadow;
@end

static BOOL Icon110ShadowUnsupportedIcon(id icon) {
    static Class widgetIconClass;
    if (!widgetIconClass) widgetIconClass = objc_getClass("SBWidgetIcon");
    static Class libraryCategoryIconClass;
    if (!libraryCategoryIconClass) libraryCategoryIconClass = objc_getClass("SBHLibraryPodCategoryIcon");
    return [icon isKindOfClass:widgetIconClass] ||
        [icon isKindOfClass:libraryCategoryIconClass];
}

static CGFloat Icon110ShadowAlpha(SBIconView *iconView, CGFloat iconAlpha) {
    if (![iconView isFolderIcon] || gShadowDragging ||
        gShadowFolderPreparing || gShadowFolderPresented ||
        gShadowFolderClosing ||
        [iconView.superview isKindOfClass:objc_getClass("SBFTouchPassThroughView")]) {
        return 0.0;
    }
    return iconAlpha;
}

static void Icon110UpdateAllShadows(void) {
    for (SBIconView *iconView in gShadowIconViews.allObjects) {
        [iconView _icon110UpdateShadowLayout];
        iconView.icon110ShadowView.alpha =
            Icon110ShadowAlpha(iconView, iconView.effectiveIconImageAlpha);
    }
    for (SBIconImageView *imageView in gShadowImageViews.allObjects) {
        [imageView _icon110UpdateCarrierShadow];
    }
}

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
%property (nonatomic, strong) UIImageView *icon110ShadowView;

- (id)initWithConfigurationOptions:(id)options listLayoutProvider:(id)provider {
    id result = %orig;
    if ([result respondsToSelector:@selector(_icon110SetUpShadow)]) {
        [result _icon110SetUpShadow];
    }
    return result;
}

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

- (BOOL)shouldShowLabelAccessoryView {
    return NO;
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
    if ([self isFolderIcon]) [self _icon110UpdateShadowLayout];
}

- (void)layoutSubviews {
    %orig;
    [self _icon110ApplyScale];
    [self _icon110HideLabel];
    [self _icon110UpdateShadowLayout];
}

- (void)_applyIconImageAlpha:(CGFloat)alpha {
    %orig(alpha);
    [self _icon110UpdateShadowLayout];
    self.icon110ShadowView.alpha = Icon110ShadowAlpha(self, alpha);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self isFolderIcon]) {
        gShadowFolderPreparing = YES;
        NSUInteger generation = gShadowFolderTransitionGeneration;
        Icon110UpdateAllShadows();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == gShadowFolderTransitionGeneration &&
                !gShadowFolderPresented && !gShadowFolderClosing) {
                gShadowFolderPreparing = NO;
                Icon110UpdateAllShadows();
            }
        });
    }
    %orig(touches, event);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig(touches, event);
    if ([self isFolderIcon] && !gShadowFolderPresented && !gShadowFolderClosing) {
        gShadowFolderPreparing = NO;
        Icon110UpdateAllShadows();
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    %orig(editing, animated);
    [self _icon110UpdateShadowLayout];
    self.icon110ShadowView.alpha =
        Icon110ShadowAlpha(self, self.effectiveIconImageAlpha);
}

- (NSArray *)dragInteraction:(id)interaction itemsForBeginningSession:(id)session {
    ++gShadowDragGeneration;
    gShadowDragging = YES;
    Icon110UpdateAllShadows();
    NSArray *items = %orig(interaction, session);
    if (items.count == 0) {
        gShadowDragging = NO;
        Icon110UpdateAllShadows();
    }
    return items;
}

- (id)dragPreviewForItem:(id)item session:(id)session {
    UITargetedDragPreview *preview = %orig(item, session);
    if (preview) preview.parameters.shadowPath = [UIBezierPath bezierPath];
    return preview;
}

- (void)dragInteraction:(id)interaction
                session:(id)session
    didEndWithOperation:(NSUInteger)operation {
    %orig(interaction, session, operation);
    NSUInteger generation = ++gShadowDragGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != gShadowDragGeneration) return;
            gShadowDragging = NO;
            Icon110UpdateAllShadows();
        });
    });
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

%new
- (void)_icon110SetUpShadow {
    UIImageView *shadowView = [[UIImageView alloc] initWithImage:gShadowImage];
    shadowView.userInteractionEnabled = NO;
    shadowView.alpha = Icon110ShadowAlpha(self, self.effectiveIconImageAlpha);
    self.icon110ShadowView = shadowView;
    [gShadowIconViews addObject:self];
    [self _icon110UpdateShadowLayout];
}

%new
- (void)_icon110UpdateShadowLayout {
    UIImageView *shadowView = self.icon110ShadowView;
    UIView *container = self.contentContainerView;
    if (!shadowView) return;
    if (![self isFolderIcon] || Icon110ShadowUnsupportedIcon(self.icon)) {
        [shadowView removeFromSuperview];
        return;
    }
    if (!container) return;

    if (Icon110ShadowAlpha(self, self.effectiveIconImageAlpha) <= 0.0) {
        [shadowView removeFromSuperview];
        return;
    }
    UIView *shadowHost = self.superview ?: self;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [shadowView.layer removeAnimationForKey:@"transform"];
    [shadowView.layer setAffineTransform:CGAffineTransformIdentity];
    [UIView performWithoutAnimation:^{
        CGPoint containerCenter = CGPointMake(CGRectGetMidX(container.bounds),
                                              CGRectGetMidY(container.bounds));
        shadowView.center = [shadowHost convertPoint:containerCenter fromView:container];
        if (shadowHost == self.superview) {
            [shadowHost insertSubview:shadowView belowSubview:self];
        } else if (shadowView.superview != shadowHost || shadowHost.subviews.firstObject != shadowView) {
            [shadowHost insertSubview:shadowView atIndex:0];
        }
    }];
    [CATransaction commit];
}

%end

%hook SBIconImageView

%property (nonatomic, strong) CALayer *icon110ShadowLayer;
%property (nonatomic, strong) NSString *icon110ShadowLocation;

- (void)setIcon:(id)icon location:(id)location animated:(BOOL)animated {
    %orig(icon, location, animated);
    self.icon110ShadowLocation = [location isKindOfClass:NSString.class]
        ? location : [location description];
    [gShadowImageViews addObject:self];
    [self _icon110UpdateCarrierShadow];
}

- (void)prepareForReuse {
    [self _icon110ClearCarrierShadow];
    self.icon110ShadowLocation = nil;
    %orig;
}

- (void)layoutSubviews {
    %orig;
    [self _icon110UpdateCarrierShadow];
}

%new
- (void)_icon110ClearCarrierShadow {
    [self.icon110ShadowLayer removeFromSuperlayer];
    self.icon110ShadowLayer = nil;
}

%new
- (void)_icon110UpdateCarrierShadow {
    NSString *location = self.icon110ShadowLocation ?: @"";
    BOOL isInsideFolder = [location containsString:@"SBIconLocationFolder"];
    BOOL isDesktopIcon = [location containsString:@"SBIconLocationRoot"] ||
                         [location containsString:@"SBIconLocationDock"];
    BOOL isFolderImage = [self isKindOfClass:objc_getClass("SBFolderIconImageView")];
    BOOL shouldShow = !gShadowDragging && !isFolderImage &&
        (isDesktopIcon || isInsideFolder) &&
        ((isInsideFolder && gShadowFolderPresented &&
          gShadowFolderOpenStable && !gShadowFolderClosing) ||
         (isDesktopIcon && !gShadowFolderPresented &&
          !gShadowFolderClosing && !gShadowFolderPreparing));
    CALayer *imageLayer = self.layer;
    CALayer *containerLayer = imageLayer.superlayer;
    if (!shouldShow || !self.window || !containerLayer || !gShadowImage) {
        [self.icon110ShadowLayer removeFromSuperlayer];
        return;
    }

    CALayer *shadowLayer = self.icon110ShadowLayer;
    if (!shadowLayer) {
        shadowLayer = [CALayer layer];
        shadowLayer.name = @"com.moxuan.icon110.shadow";
        shadowLayer.contents = (__bridge id)gShadowImage.CGImage;
        shadowLayer.contentsScale = gShadowImage.scale;
        shadowLayer.contentsGravity = kCAGravityResizeAspect;
        shadowLayer.masksToBounds = NO;
        self.icon110ShadowLayer = shadowLayer;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSUInteger shadowIndex = [containerLayer.sublayers indexOfObjectIdenticalTo:shadowLayer];
    NSUInteger imageIndex = [containerLayer.sublayers indexOfObjectIdenticalTo:imageLayer];
    if (shadowLayer.superlayer != containerLayer || imageIndex == NSNotFound ||
        shadowIndex == NSNotFound || shadowIndex + 1 != imageIndex) {
        [shadowLayer removeFromSuperlayer];
        [containerLayer insertSublayer:shadowLayer below:imageLayer];
    }
    shadowLayer.bounds = (CGRect){CGPointZero, gShadowImage.size};
    shadowLayer.position = imageLayer.position;
    shadowLayer.anchorPoint = imageLayer.anchorPoint;
    shadowLayer.transform = imageLayer.transform;
    shadowLayer.opacity = imageLayer.opacity;
    shadowLayer.hidden = imageLayer.hidden;
    [CATransaction commit];
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
- (void)setOpen:(BOOL)open;
@end

%hook SBFolderController

- (void)pushFolderIcon:(id)folderIcon
              location:(id)location
              animated:(BOOL)animated
            completion:(Icon110Completion)completion {
    Icon110BeginFolderTransition();
    NSUInteger generation = ++gShadowFolderTransitionGeneration;
    gShadowFolderPreparing = YES;
    gShadowFolderOpenStable = NO;
    gShadowFolderClosing = NO;
    gShadowFolderPresented = YES;
    Icon110UpdateAllShadows();
    Icon110Completion wrappedCompletion = ^{
        Icon110EndFolderTransition();
        if (completion) completion();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != gShadowFolderTransitionGeneration ||
                !gShadowFolderPresented || gShadowFolderClosing) return;
            gShadowFolderPreparing = NO;
            gShadowFolderOpenStable = YES;
            for (SBIconView *iconView in gShadowIconViews.allObjects) {
                if (![iconView.location containsString:@"SBIconLocationFolder"]) continue;
                [iconView.contentContainerView setNeedsLayout];
                [iconView.contentContainerView layoutIfNeeded];
                [iconView _icon110ApplyScale];
                [iconView _icon110UpdateShadowLayout];
                iconView.icon110ShadowView.alpha =
                    Icon110ShadowAlpha(iconView, iconView.effectiveIconImageAlpha);
            }
            Icon110UpdateAllShadows();
        });
    };
    %orig(folderIcon, location, animated, wrappedCompletion);
}

- (void)popFolderAnimated:(BOOL)animated
               completion:(Icon110Completion)completion {
    Icon110BeginFolderTransition();
    NSUInteger generation = ++gShadowFolderTransitionGeneration;
    gShadowFolderPreparing = YES;
    gShadowFolderOpenStable = NO;
    gShadowFolderPresented = NO;
    gShadowFolderClosing = YES;
    Icon110UpdateAllShadows();
    Icon110Completion wrappedCompletion = ^{
        Icon110EndFolderTransition();
        if (completion) completion();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == gShadowFolderTransitionGeneration) {
                gShadowFolderClosing = NO;
                gShadowFolderPresented = NO;
                gShadowFolderPreparing = NO;
                gShadowFolderOpenStable = NO;
                Icon110UpdateAllShadows();
            }
        });
    };
    %orig(animated, wrappedCompletion);
}

- (void)setOpen:(BOOL)open {
    %orig(open);
    if (open || gShadowFolderClosing || !gShadowFolderPresented) return;
    gShadowFolderPresented = NO;
    gShadowFolderClosing = NO;
    gShadowFolderPreparing = NO;
    gShadowFolderOpenStable = NO;
    Icon110UpdateAllShadows();
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

    // During a light/dark appearance change SpringBoard rebuilds the Dock
    // material after this callback returns. Reapply once after that deferred
    // update so the background stays transparent without waiting for the next
    // touch-driven layout pass.
    __weak SBDockView *weakDockView = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SBDockView *dockView = weakDockView;
        if (dockView.window) {
            [dockView setBackgroundAlpha:0.0];
        }
    });
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

%hook SBFolderIconImageView

- (void)setBackgroundView:(id)backgroundView {
    UIView *transparentView = [UIView new];
    transparentView.userInteractionEnabled = NO;
    transparentView.backgroundColor = UIColor.clearColor;
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

%ctor {
    gShadowIconViews = [NSHashTable weakObjectsHashTable];
    gShadowImageViews = [NSHashTable weakObjectsHashTable];
    gShadowImage = [UIImage imageWithContentsOfFile:
        jbroot(@"/Library/Themes/iconShadow@3x.png")];
}
