#pragma once
#import "ENRMFeatureFlags.h"
#import "ENRMUIKit.h"
#import "StyleConfig.h"
#include <TargetConditionals.h>

#if ENRICHED_MARKDOWN_MATH && !TARGET_OS_OSX

NS_ASSUME_NONNULL_BEGIN

/// Covers math attachments that are wider than their line (equations in
/// list items, blockquotes, etc.) with horizontally scrollable
/// ENRMMathContainerView overlays. Follows the same layout-driven update
/// lifecycle as ENRMSpoilerOverlayManager.
@interface ENRMMathOverlayManager : NSObject

- (instancetype)initWithTextView:(ENRMPlatformTextView *)textView config:(StyleConfig *)config;

- (void)setNeedsUpdate;
- (void)updateIfNeeded;
- (void)removeAllOverlays;

@end

NS_ASSUME_NONNULL_END

#endif
