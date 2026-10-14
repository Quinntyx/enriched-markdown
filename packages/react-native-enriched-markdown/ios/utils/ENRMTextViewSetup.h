#pragma once
#import "ENRMUIKit.h"
#import "LastElementUtils.h"
#import "StyleConfig.h"
#import "TextViewLayoutManager.h"
#import <React/RCTUtils.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static inline void ENRMAttachLayoutManager(ENRMPlatformTextView *textView, StyleConfig *_Nullable config)
{
  NSLayoutManager *layoutManager = textView.layoutManager;
  if (layoutManager == nil) {
    return;
  }
  layoutManager.allowsNonContiguousLayout = NO;
  object_setClass(layoutManager, [TextViewLayoutManager class]);
  if (config != nil) {
    [layoutManager setValue:config forKey:@"config"];
  }
}

static inline void ENRMDetachLayoutManager(ENRMPlatformTextView *textView)
{
  NSLayoutManager *layoutManager = textView.layoutManager;
  if (layoutManager != nil && [object_getClass(layoutManager) isEqual:[TextViewLayoutManager class]]) {
    [layoutManager setValue:nil forKey:@"config"];
    object_setClass(layoutManager, [NSLayoutManager class]);
  }
}

static inline BOOL ENRMTextLayoutHasSoftWrap(NSLayoutManager *layoutManager, NSAttributedString *text)
{
  NSUInteger glyphCount = [layoutManager numberOfGlyphs];
  if (glyphCount == 0) {
    return NO;
  }

  NSString *string = text.string;
  NSUInteger glyphIndex = 0;
  while (glyphIndex < glyphCount) {
    NSRange lineGlyphRange;
    [layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&lineGlyphRange];

    NSUInteger nextGlyphIndex = NSMaxRange(lineGlyphRange);
    if (nextGlyphIndex < glyphCount) {
      NSUInteger nextCharacterIndex = [layoutManager characterIndexForGlyphAtIndex:nextGlyphIndex];
      BOOL hardBreak = NO;
      if (nextCharacterIndex > 0 && nextCharacterIndex <= string.length) {
        unichar previousCharacter = [string characterAtIndex:nextCharacterIndex - 1];
        hardBreak = previousCharacter == '\n' || previousCharacter == '\r' || previousCharacter == 0x2028 ||
                    previousCharacter == 0x2029;
      }
      if (!hardBreak) {
        return YES;
      }
    }

    if (nextGlyphIndex <= glyphIndex) {
      break;
    }
    glyphIndex = nextGlyphIndex;
  }

  return NO;
}

/// Turns a raw TextKit layout pass into the final measured size. Shared by
/// the view-backed path (`ENRMMeasureMarkdownText`) and the view-free path
/// (`ENRMMeasureMarkdownViewFree`) so both measure with one algorithm.
///
/// Steps, in order:
/// - Soft-wrap pin: returning a tight usedRect width after wrapping would let flexShrink
///   narrow the view below maxWidth, re-wrapping at the narrower width and
///   mismatching the measured height. Explicit line breaks retain their tight width.
/// - Optionally subtract the extra line fragment (iOS counts a trailing
///   newline's empty line fragment into usedRect). Read-only markdown passes
///   YES; text input passes NO so trailing newlines keep a blank line (RN Text
///   parity).
/// - Add code-block padding when the last element is a code block, and the
///   trailing margin when enabled.
/// - Round up to the pixel grid of `scale` (pass `RCTScreenScale()` on main;
///   off-main callers must pass `LayoutContext::pointScaleFactor` instead —
///   `RCTScreenScale()` dispatch_syncs to main on first use, which the
///   measure path must never do, see issue #550).
static inline CGSize ENRMFinalizeMeasuredTextSize(ENRMTextLayoutResult layout, NSLayoutManager *layoutManager,
                                                  NSAttributedString *text, CGFloat maxWidth, StyleConfig *config,
                                                  BOOL allowTrailingMargin, CGFloat lastElementMarginBottom,
                                                  BOOL subtractExtraLineFragment, CGFloat scale)
{
  CGFloat measuredWidth = layout.usedRect.size.width;
  CGFloat measuredHeight = layout.usedRect.size.height;

  if (ENRMTextLayoutHasSoftWrap(layoutManager, text)) {
    measuredWidth = maxWidth;
  }

  if (subtractExtraLineFragment && !CGRectIsEmpty(layout.extraLineFragmentRect)) {
    measuredHeight -= layout.extraLineFragmentRect.size.height;
  }

  if (isLastElementCodeBlock(text)) {
    measuredHeight += [config codeBlockPadding];
  }

  if (allowTrailingMargin && lastElementMarginBottom > 0) {
    measuredHeight += lastElementMarginBottom;
  }

  return CGSizeMake(ceil(measuredWidth * scale) / scale, ceil(measuredHeight * scale) / scale);
}

static inline CGSize ENRMMeasureMarkdownText(ENRMPlatformTextView *textView, CGFloat maxWidth, StyleConfig *config,
                                             BOOL allowTrailingMargin, CGFloat lastElementMarginBottom)
{
  NSAttributedString *text = ENRMGetAttributedText(textView);
  if (text.length == 0) {
    return CGSizeZero;
  }

  ENRMTextLayoutResult layout = ENRMMeasureTextLayout(textView, maxWidth);
  return ENRMFinalizeMeasuredTextSize(layout, textView.layoutManager, text, maxWidth, config, allowTrailingMargin,
                                      lastElementMarginBottom, YES, RCTScreenScale());
}

NS_ASSUME_NONNULL_END
