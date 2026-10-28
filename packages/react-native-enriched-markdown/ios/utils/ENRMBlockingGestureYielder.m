#import "ENRMBlockingGestureYielder.h"
#import <React/UIView+React.h>
#import <objc/message.h>

// The exact slice of RNGestureHandlerManager (the react-native-gesture-handler
// pod) this feature uses, declared on a private protocol so the pod's headers
// are never linked into this one. Read back from the vendored RNGH 3.3.0
// sources: managers receive create/attach/drop directly (RNGH's own
// native-detached buttons do the same, with RNGestureHandlerActionTypeNone);
// the module-level wrappers differ, and those stage work for the view
// registry, which plain subviews like ours never register in.
@protocol ENRMRNGestureHandlerManager <NSObject>
- (void)createGestureHandler:(NSString *)handlerName
                         tag:(NSNumber *)handlerTag
                      config:(NSDictionary *)config;
- (void)attachHandlerForDetectorWithTag:(NSNumber *)handlerTag
                                 toView:(UIView *)view
                         withActionType:(NSInteger)actionType
                       withHostDetector:(nullable UIView *)hostDetector;
- (void)updateGestureHandlerRelations:(NSNumber *)handlerTag relations:(NSDictionary *)relations;
- (void)dropGestureHandler:(NSNumber *)handlerTag;
@end

// Keyed to the vendored RNGH 3.3.0 APIs.
static NSString *const ENRMYielderHandlerName = @"NativeViewGestureHandler";
static NSString *const ENRMYielderBlocksHandlersKey = @"blocksHandlers";
// RNGestureHandlerActionTypeNone: a native-detached helper dispatches no events.
static NSInteger const ENRMYielderActionTypeNone = 0;

@implementation ENRMBlockingGestureYielder {
  __weak ENRMHorizontalScrollView *_scrollView;
  NSArray<NSNumber *> *_Nullable (^_blockingGestureTags)(void);
  BOOL _overflowing;
  BOOL _registered;
  // The shared dynamicProps box copies its arrays on write, so pointer
  // equality between tag arrays never holds; contents are compared instead.
  NSArray<NSNumber *> *_configuredTags;
  NSNumber *_handlerTag;
}

- (instancetype)initWithScrollView:(ENRMHorizontalScrollView *)scrollView
              blockingGestureTags:(NSArray<NSNumber *> *_Nullable (^)(void))blockingGestureTags
{
  self = [super init];
  if (self) {
    _scrollView = scrollView;
    _blockingGestureTags = blockingGestureTags;
  }
  return self;
}

- (void)dealloc
{
  [self drop];
}

- (void)setOverflowing:(BOOL)overflowing
{
  if (_overflowing == overflowing) {
    return;
  }
  _overflowing = overflowing;
  [self sync];
}

- (void)onWindowAttached
{
  [self sync];
}

- (void)onWindowDetached
{
  [self drop];
}

- (void)onBlockingGestureTagsChanged
{
  if (!_overflowing) {
    return;
  }
  [self sync];
}

// One pass re-evaluates every input (overflow, tags, attach, relations) and
// skips native and reflective work whenever nothing changed.
- (void)sync
{
  if (!_overflowing) {
    [self drop];
    return;
  }
  if (_scrollView.window == nil) {
    return;
  }
  NSArray<NSNumber *> *tags = _blockingGestureTags() ?: @[];
  // No blocking gesture at all: with nothing to yield to, a registered
  // handler would only shadow the usual touch dispatch.
  if (tags.count == 0) {
    [self drop];
    return;
  }
  if (_registered && [_configuredTags isEqualToArray:tags]) {
    return;
  }

  id<ENRMRNGestureHandlerManager> manager = [self gestureHandlerManager];
  if (manager == nil) {
    return;
  }
  if (!_registered) {
    [self registerWithGestureHandlerManager:manager];
  }
  if (![_configuredTags isEqualToArray:tags]) {
    // An attached handler keeps its relations across re-configuration because
    // updateRelations replaces the blocksHandlers array whole (see RNGH).
    [manager updateGestureHandlerRelations:_handlerTag
                                 relations:@{ENRMYielderBlocksHandlersKey : tags}];
    _configuredTags = tags;
  }
}

- (void)registerWithGestureHandlerManager:(id<ENRMRNGestureHandlerManager>)manager
{
  // RNGH's relation and event paths touch the attached view's reactTag once
  // the recognizer fires; native subviews are born without one, so mint a tag
  // from a holder range far above any real React view tag (the scroll view is
  // not a Fabric component view, so there is no real tag to reuse).
  // ActionTypeNone consumes the events that would carry the minted one.
  static NSInteger nextYielderViewTag = 0x40000000;
  _handlerTag = @(-(nextYielderViewTag++));
  _scrollView.reactTag = @(-_handlerTag.longLongValue);
  [manager createGestureHandler:ENRMYielderHandlerName tag:_handlerTag config:@{}];
  [manager attachHandlerForDetectorWithTag:_handlerTag
                                    toView:_scrollView
                            withActionType:ENRMYielderActionTypeNone
                         withHostDetector:nil];
  _configuredTags = nil;
  _registered = YES;
}

- (void)drop
{
  if (!_registered) {
    return;
  }
  _registered = NO;
  _configuredTags = nil;
  id<ENRMRNGestureHandlerManager> manager = [self gestureHandlerManager];
  if (manager != nil) {
    [manager dropGestureHandler:_handlerTag];
  }
  _handlerTag = nil;
}

// The RNGestureHandlerModule class is unavailable whenever the pod is not
// installed, which turns the feature permanently off for this binding; a
// missing manager only means the module has not been initialized yet, so that
// case is retried on the next sync rather than latched. The manager is never
// cached: an RN reload nulls its registry entry and deallocates it.
- (nullable id<ENRMRNGestureHandlerManager>)gestureHandlerManager
{
  static Class moduleClass;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    moduleClass = NSClassFromString(@"RNGestureHandlerModule");
  });
  if (moduleClass == nil ||
      ![moduleClass respondsToSelector:@selector(handlerManagerForModuleId:)]) {
    return nil;
  }
  // The managers are keyed by an internal, incrementing module id on a static
  // map of the module class; a bounded scan over the ids is the only public
  // route to one. Nulled entries (an RN reload) read here as nil and are
  // skipped.
  static const int kENRMYielderMaxModuleIds = 16;
  IMP lookup = [moduleClass methodForSelector:@selector(handlerManagerForModuleId:)];
  for (int moduleId = 0; moduleId < kENRMYielderMaxModuleIds; moduleId++) {
    id manager = ((id (*)(Class, SEL, int))lookup)(moduleClass, @selector(handlerManagerForModuleId:), moduleId);
    if (manager != nil) {
      return manager;
    }
  }
  return nil;
}

@end
