#pragma once
#import "ENRMUIKit.h"

@class ENRMHorizontalScrollView;

NS_ASSUME_NONNULL_BEGIN

/**
 * The root notifies a scrollable block container through this protocol when the
 * blockingGestureTags prop changed, so an attached yielder re-runs its
 * relations (nothing else is needed when nothing is attached yet). The iOS
 * counterpart of Android's BlockingGestureYielderHost.
 */
@protocol ENRMBlockingGestureYielderHost <NSObject>
- (void)blockingGestureTagsChanged;
@end

/**
 * Why the handler: the app's root Pan drawer (whose tags arrive as the
 * blockingGestureTags prop on ENRMDynamicBlockProps) cancels native touches it
 * activates, so an overflowing table or code block could never scroll
 * horizontally. This binding registers a plain RNGH NativeViewGestureHandler on
 * the block's scroll view with `blocksHandlers` = the drawer tags, making the
 * drawer's handlers wait for that native scroll to fail instead: while the
 * block overflows, its own scrolling wins a touch started on it; without
 * overflow no handler exists and touches stream to the drawer normally.
 *
 * Handler tags are the negative of the scroll view's synthetic reactTag,
 * mirroring the RNGH native-side helper convention, and cannot collide with JS
 * handler tags (positive). RNGH is a peer module rather than a library
 * dependency, so the module class is resolved through NSClassFromString once
 * and its manager is looked up per call; the pod's own classes are never
 * linked into this pod. Absent at
 * runtime (an app without RNGH, or before its first initialize), every call
 * degrades to a no-op. Calls run from the main thread (mount, layout, window
 * callbacks), so no extra serialization is needed.
 */
@interface ENRMBlockingGestureYielder : NSObject

// The tags getter is consulted at use-time (the shared, never-copied
// ENRMDynamicBlockProps), so an attached yielder always sees the current prop.
- (instancetype)initWithScrollView:(ENRMHorizontalScrollView *)scrollView
              blockingGestureTags:(NSArray<NSNumber *> *_Nullable (^)(void))blockingGestureTags;

- (void)setOverflowing:(BOOL)overflowing;

// The registry entry survives window detach, so a reattached block must
// re-register here (layout runs after this and re-arms overflow too).
- (void)onWindowAttached;
- (void)onWindowDetached;

// Forwards from the ENRMBlockingGestureYielderHost callback.
- (void)onBlockingGestureTagsChanged;

@end

NS_ASSUME_NONNULL_END
