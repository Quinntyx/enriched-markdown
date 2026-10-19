// Adapted from pingdotgg/t3chat bf1ddf5, preserving inline formula metrics and mode.
#import "ENRMMathOverlayManager.h"

#if ENRICHED_MARKDOWN_MATH && !TARGET_OS_OSX

#import "ENRMAccessibilityLabels.h"
#import "ENRMMarkdownTextView.h"
#import "ENRMMathContainerView.h"
#import "ENRMMathInlineAttachment.h"

@implementation ENRMMathOverlayManager {
  __weak ENRMPlatformTextView *_textView;
  StyleConfig *_config;
  // Keyed by occurrence index + latex (not position), so an overlay survives
  // vertical reflow during streaming and keeps its scroll offset.
  NSMutableDictionary<NSString *, ENRMMathContainerView *> *_overlaysByKey;
  BOOL _needsUpdate;
}

- (instancetype)initWithTextView:(ENRMPlatformTextView *)textView config:(StyleConfig *)config
{
  if (self = [super init]) {
    _textView = textView;
    _config = config;
    _overlaysByKey = [NSMutableDictionary new];
  }
  return self;
}

- (void)setNeedsUpdate
{
  _needsUpdate = YES;
}

- (void)updateIfNeeded
{
  if (!_needsUpdate)
    return;
  ENRMPlatformTextView *textView = _textView;
  // Intentionally keep _needsUpdate=YES when the text view is unavailable
  // or has zero width — the update will be retried on the next layout pass.
  if (!textView || textView.bounds.size.width <= 0)
    return;
  [self updateOverlays];
}

- (void)removeAllOverlays
{
  for (ENRMMathContainerView *overlay in _overlaysByKey.allValues) {
    [overlay removeFromSuperview];
  }
  [_overlaysByKey removeAllObjects];
}

#pragma mark - Private

- (void)updateOverlays
{
  _needsUpdate = NO;

  ENRMPlatformTextView *textView = _textView;
  NSTextStorage *textStorage = textView.textStorage;
  if (!textStorage || textStorage.length == 0) {
    [self removeAllOverlays];
    return;
  }

  NSLayoutManager *layoutManager = textView.layoutManager;
  NSTextContainer *textContainer = textView.textContainer;
  [layoutManager ensureLayoutForTextContainer:textContainer];

  UIEdgeInsets inset = textView.textContainerInset;

  NSMutableSet<NSString *> *desiredKeys = [NSMutableSet new];
  __block NSUInteger occurrence = 0;

  [textStorage
      enumerateAttribute:NSAttachmentAttributeName
                 inRange:NSMakeRange(0, textStorage.length)
                 options:0
              usingBlock:^(id value, NSRange charRange, BOOL *stop) {
                if (![value isKindOfClass:[ENRMMathInlineAttachment class]])
                  return;

                ENRMMathInlineAttachment *attachment = (ENRMMathInlineAttachment *)value;
                NSUInteger index = occurrence++;
                if (!attachment.overflowsLine)
                  return;

                NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
                if (glyphRange.location == NSNotFound || glyphRange.length == 0)
                  return;

                CGRect textRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:textContainer];
                CGRect frame = CGRectMake(textRect.origin.x + inset.left, textRect.origin.y + inset.top,
                                          textRect.size.width, textRect.size.height);
                if (frame.size.width <= 0 || frame.size.height <= 0)
                  return;

                NSString *key =
                    [NSString stringWithFormat:@"%lu|%@|%d|%g|%@", (unsigned long)index, attachment.latex,
                                               attachment.displayMode, attachment.fontSize, attachment.mathTextColor];
                [desiredKeys addObject:key];

                ENRMMathContainerView *overlay = self->_overlaysByKey[key];
                if (!overlay) {
                  overlay = [[ENRMMathContainerView alloc] initWithConfig:self->_config];
                  [overlay applyInlineLatex:attachment.latex
                                displayMode:attachment.displayMode
                                   fontSize:attachment.fontSize
                                      color:attachment.mathTextColor ?: UIColor.labelColor];
                  overlay.accessibilityLabels = [[ENRMAccessibilityLabels alloc] init];
                  [textView addSubview:overlay];
                  self->_overlaysByKey[key] = overlay;
                }
                ENRMMarkdownTextView *markdownTextView = (ENRMMarkdownTextView *)textView;
                if (markdownTextView.mathDynamicProps)
                  overlay.dynamicProps = markdownTextView.mathDynamicProps;
                if (markdownTextView.mathAccessibilityLabels)
                  overlay.accessibilityLabels = markdownTextView.mathAccessibilityLabels;
                overlay.frame = frame;
              }];

  NSMutableArray<NSString *> *staleKeys = [NSMutableArray new];
  for (NSString *key in _overlaysByKey) {
    if (![desiredKeys containsObject:key]) {
      [staleKeys addObject:key];
    }
  }
  for (NSString *key in staleKeys) {
    [_overlaysByKey[key] removeFromSuperview];
    [_overlaysByKey removeObjectForKey:key];
  }
}

@end

#endif
