#import "UIKitUtils.h"

#import <ObjCRuntimeUtils/RuntimeUtils.h>

#import <objc/runtime.h>

#if TARGET_IPHONE_SIMULATOR
UIKIT_EXTERN float UIAnimationDragCoefficient();
#endif

double animationDurationFactorImpl() {
#if TARGET_IPHONE_SIMULATOR
    return (double)UIAnimationDragCoefficient();
#endif   
    return 1.0f;
}

@interface CASpringAnimation ()

@end

@implementation CASpringAnimation (AnimationUtils)

- (CGFloat)valueAt:(CGFloat)t {
    static dispatch_once_t onceToken;
    static float (*impl)(id, float) = NULL;
    static double (*dimpl)(id, double) = NULL;
    dispatch_once(&onceToken, ^{
        Method method = class_getInstanceMethod([CASpringAnimation class], NSSelectorFromString([@"_" stringByAppendingString:@"solveForInput:"]));
        if (method) {
            const char *encoding = method_getTypeEncoding(method);
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
            const char *argType = [signature getArgumentTypeAtIndex:2];
            if (strncmp(argType, "f", 1) == 0) {
                impl = (float (*)(id, float))method_getImplementation(method);
            } else if (strncmp(argType, "d", 1) == 0) {
                dimpl = (double (*)(id, double))method_getImplementation(method);
            }
        }
    });
    if (impl) {
        float result = impl(self, (float)t);
        return (CGFloat)result;
    } else if (dimpl) {
        double result = dimpl(self, (double)t);
        return (CGFloat)result;
    }
    return t;
}

@end

CABasicAnimation * _Nonnull makeSpringAnimationImpl(NSString * _Nonnull keyPath) {
    CASpringAnimation *springAnimation = [CASpringAnimation animationWithKeyPath:keyPath];
    springAnimation.mass = 3.0f;
    springAnimation.stiffness = 1000.0f;
    springAnimation.damping = 500.0f;
    springAnimation.duration = 0.5;
    springAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    
    return springAnimation;
}

CABasicAnimation * _Nonnull makeSpringBounceAnimationImpl(NSString * _Nonnull keyPath, CGFloat initialVelocity, CGFloat damping) {
    CASpringAnimation *springAnimation = [CASpringAnimation animationWithKeyPath:keyPath];
    springAnimation.mass = 5.0f;
    springAnimation.stiffness = 900.0f;
    springAnimation.damping = damping;
    static bool canSetInitialVelocity = true;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        canSetInitialVelocity = [springAnimation respondsToSelector:@selector(setInitialVelocity:)];
    });
    if (canSetInitialVelocity) {
        springAnimation.initialVelocity = initialVelocity;
        springAnimation.duration = springAnimation.settlingDuration;
    } else {
        springAnimation.duration = 0.1;
    }
    springAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    return springAnimation;
}

CGFloat springAnimationValueAtImpl(CABasicAnimation * _Nonnull animation, CGFloat t) {
    return [(CASpringAnimation *)animation valueAt:t];
}

@interface CustomBlurEffect : UIBlurEffect

+ (id)effectWithStyle:(long long)arg1;

@end

static void setField(CustomBlurEffect *object, NSString *name, double value) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [[object class] instanceMethodSignatureForSelector:selector];
    if (signature == nil) {
        return;
    }
    
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
    [inv setSelector:selector];
    [inv setArgument:&value atIndex:2];
    [inv setTarget:object];
    [inv invoke];
}

static void setNilField(CustomBlurEffect *object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [[object class] instanceMethodSignatureForSelector:selector];
    if (signature == nil) {
        return;
    }
    
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
    [inv setSelector:selector];
    id value = nil;
    [inv setArgument:&value atIndex:2];
    [inv setTarget:object];
    [inv invoke];
}

static void setBoolField(NSObject *object, NSString *name, BOOL value) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [[object class] instanceMethodSignatureForSelector:selector];
    if (signature == nil) {
        return;
    }
    
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
    [inv setSelector:selector];
    [inv setArgument:&value atIndex:2];
    [inv setTarget:object];
    [inv invoke];
}

UIBlurEffect *makeCustomZoomBlurEffectImpl(bool isLight) {
    if (@available(iOS 13.0, *)) {
        if (isLight) {
            return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
        } else {
            return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        }
    } else if (@available(iOS 11.0, *)) {
        NSString *string = [@[@"_", @"UI", @"Custom", @"BlurEffect"] componentsJoinedByString:@""];
        CustomBlurEffect *result = (CustomBlurEffect *)[NSClassFromString(string) effectWithStyle:0];
        
        setField(result, [@[@"set", @"BlurRadius", @":"] componentsJoinedByString:@""], 10.0);
        setNilField(result, [@[@"set", @"Color", @"Tint", @":"] componentsJoinedByString:@""]);
        setField(result, [@[@"set", @"Color", @"Tint", @"Alpha", @":"] componentsJoinedByString:@""], 0.0);
        setField(result, [@[@"set", @"Darkening", @"Tint", @"Alpha", @":"] componentsJoinedByString:@""], 0.0);
        setField(result, [@[@"set", @"Grayscale", @"Tint", @"Alpha", @":"] componentsJoinedByString:@""], 0.0);
        setField(result, [@[@"set", @"Saturation", @"Delta", @"Factor", @":"] componentsJoinedByString:@""], 1.0);
        
        if ([UIScreen mainScreen].scale > 2.5f) {
            setField(result, @"setScale:", 0.3);
        } else {
            setField(result, @"setScale:", 0.5);
        }
        
        return result;
    } else {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    }
}

void applySmoothRoundedCornersImpl(CALayer * _Nonnull layer) {
    if (@available(iOS 13.0, *)) {
        layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        setBoolField(layer, [@[@"set", @"Continuous", @"Corners", @":"] componentsJoinedByString:@""], true);
    }
}

UIView<UIKitPortalViewProtocol> * _Nullable makePortalView(bool matchPosition) {
    static Class portalViewClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        portalViewClass = NSClassFromString([@[@"_", @"UI", @"Portal", @"View"] componentsJoinedByString:@""]);
    });
    if (!portalViewClass) {
        return nil;
    }
    UIView<UIKitPortalViewProtocol> *view = [[portalViewClass alloc] init];
    if (!view) {
        return nil;
    }
    
    if (@available(iOS 14.0, *)) {
        view.forwardsClientHitTestingToSourceView = false;
    }
    view.matchesPosition = matchPosition;
    view.matchesTransform = matchPosition;
    view.matchesAlpha = false;
    if (@available(iOS 14.0, *)) {
        view.allowsHitTesting = false;
    }
    
    return view;
}

bool isViewPortalView(UIView * _Nonnull view) {
    static Class portalViewClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        portalViewClass = NSClassFromString([@[@"_", @"UI", @"Portal", @"View"] componentsJoinedByString:@""]);
    });
    if ([view isKindOfClass:portalViewClass]) {
        return true;
    } else {
        return false;
    }
}

UIView * _Nullable getPortalViewSourceView(UIView * _Nonnull portalView) {
    if (!isViewPortalView(portalView)) {
        return nil;
    }
    UIView<UIKitPortalViewProtocol> *view = (UIView<UIKitPortalViewProtocol> *)portalView;
    return view.sourceView;
}

@protocol GraphicsFilterProtocol <NSObject>
    
- (NSObject * _Nullable)filterWithName:(NSString * _Nonnull)name;

@end

NSObject * _Nullable makeBlurFilter() {
    return [(id<GraphicsFilterProtocol>)NSClassFromString(@"CAFilter") filterWithName:@"gaussianBlur"];
}

NSObject * _Nullable makeLuminanceToAlphaFilter() {
    return [(id<GraphicsFilterProtocol>)NSClassFromString(@"CAFilter") filterWithName:@"luminanceToAlpha"];
}

NSObject * _Nullable makeColorInvertFilter() {
    return [(id<GraphicsFilterProtocol>)NSClassFromString(@"CAFilter") filterWithName:@"colorInvert"];
}

NSObject * _Nullable makeMonochromeFilter() {
    return [(id<GraphicsFilterProtocol>)NSClassFromString(@"CAFilter") filterWithName:@"colorMonochrome"];
}

static const void *layerDisableScreenshotsKey = &layerDisableScreenshotsKey;

void setLayerDisableScreenshots(CALayer * _Nonnull layer, bool disableScreenshots) {
    static UITextField *textField = nil;
    static UIView *secureView = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        textField = [[UITextField alloc] init];
        for (UIView *subview in textField.subviews) {
            if ([NSStringFromClass([subview class]) containsString:@"TextLayoutCanvasView"]) {
                secureView = subview;
                break;
            }
        }
    });
    if (secureView == nil) {
        return;
    }
    
    CALayer *previousLayer = secureView.layer;
    [secureView setValue:layer forKey:@"layer"];
    if (disableScreenshots) {
        textField.secureTextEntry = false;
        textField.secureTextEntry = true;
    } else {
        textField.secureTextEntry = true;
        textField.secureTextEntry = false;
    }
    [secureView setValue:previousLayer forKey:@"layer"];
    
    [layer setAssociatedObject:@(disableScreenshots) forKey:layerDisableScreenshotsKey associationPolicy:NSObjectAssociationPolicyRetain];
}

bool getLayerDisableScreenshots(CALayer * _Nonnull layer) {
    id result = [layer associatedObjectForKey:layerDisableScreenshotsKey];
    if ([result respondsToSelector:@selector(boolValue)]) {
        return [(NSNumber *)result boolValue];
    } else {
        return false;
    }
}

void setLayerContentsMaskMode(CALayer * _Nonnull layer, bool maskMode) {
    static NSString *key = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        key = [@"contents" stringByAppendingString:@"Swizzle"];
    });
    if (key == nil) {
        return;
    }
    if (maskMode) {
        [layer setValue:@"AAAA" forKey:key];
    } else {
        [layer setValue:@"RGBA" forKey:key];
    }
}
