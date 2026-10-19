#import "CodeBackground.h"
#import "ENRMUIKit.h"
#import "RenderContext.h"

NSString *const CodeAttributeName = @"Code";
NSString *const CodePaddingAttributeName = @"ENRMCodePadding";

static const CGFloat kCodeBackgroundCornerRadius = 2.0;
static const CGFloat kCodeBackgroundBorderWidth = 0.5;
// Extra chip height beyond the code font's ascent/descent, per side, as a
// fraction of the code font size.
static const CGFloat kCodeBackgroundVerticalPaddingScale = 0.1;

@implementation CodeBackground {
  StyleConfig *_config;
}

- (instancetype)initWithConfig:(StyleConfig *)config
{
  self = [super init];
  if (self) {
    _config = config;
  }
  return self;
}

- (void)drawBackgroundsForGlyphRange:(NSRange)glyphsToShow
                       layoutManager:(NSLayoutManager *)layoutManager
                       textContainer:(NSTextContainer *)textContainer
                             atPoint:(CGPoint)origin
{
  RCTUIColor *backgroundColor = _config.codeBackgroundColor;
  if (!backgroundColor)
    return;

  NSTextStorage *textStorage = layoutManager.textStorage;
  NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphsToShow actualGlyphRange:NULL];
  if (charRange.location == NSNotFound || charRange.length == 0)
    return;

  [textStorage enumerateAttribute:CodeAttributeName
                          inRange:NSMakeRange(0, textStorage.length)
                          options:0
                       usingBlock:^(id value, NSRange range, BOOL *stop) {
                         if (!value || range.length == 0)
                           return;
                         if (NSIntersectionRange(range, charRange).length == 0)
                           return;

                         [self drawCodeBackgroundForRange:range
                                            layoutManager:layoutManager
                                            textContainer:textContainer
                                                  atPoint:origin
                                          backgroundColor:backgroundColor
                                              borderColor:self->_config.codeBorderColor];
                       }];
}

- (void)drawCodeBackgroundForRange:(NSRange)range
                     layoutManager:(NSLayoutManager *)layoutManager
                     textContainer:(NSTextContainer *)textContainer
                           atPoint:(CGPoint)origin
                   backgroundColor:(RCTUIColor *)backgroundColor
                       borderColor:(RCTUIColor *)borderColor
{
  NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
  if (glyphRange.location == NSNotFound || glyphRange.length == 0)
    return;

  // The code run starts and ends with half-size padding characters, so read
  // the font from an inner character to get the real code font metrics.
  NSUInteger fontIndex = range.location + (range.length > 2 ? 1 : 0);
  UIFont *codeFont = [layoutManager.textStorage attribute:NSFontAttributeName atIndex:fontIndex effectiveRange:NULL];
  CGFloat verticalPadding = codeFont ? codeFont.pointSize * kCodeBackgroundVerticalPaddingScale : 0;

  [layoutManager
      enumerateLineFragmentsForGlyphRange:glyphRange
                               usingBlock:^(CGRect rect, CGRect usedRect, NSTextContainer *tc, NSRange lineRange,
                                            BOOL *stop) {
                                 NSRange intersect = NSIntersectionRange(lineRange, glyphRange);
                                 if (intersect.length == 0)
                                   return;

                                 BOOL isFirst = (intersect.location == glyphRange.location);
                                 BOOL isLast = (NSMaxRange(intersect) == NSMaxRange(glyphRange));

                                 CGRect finalRect;
                                 if (isFirst || isLast) {
                                   // Precise bounds are only required for the start and end of the span
                                   CGRect textRect = [layoutManager boundingRectForGlyphRange:intersect
                                                                              inTextContainer:textContainer];
                                   finalRect = CGRectMake(textRect.origin.x + origin.x, textRect.origin.y + origin.y,
                                                          textRect.size.width, textRect.size.height);

                                   // For multi-line, extend the first line to the right edge of the fragment
                                   if (isFirst && !isLast) {
                                     finalRect.size.width =
                                         (usedRect.origin.x + usedRect.size.width + origin.x) - finalRect.origin.x;
                                   }
                                 } else {
                                   // OPTIMIZATION: Middle lines use the usedRect of the fragment directly
                                   finalRect = CGRectMake(usedRect.origin.x + origin.x, usedRect.origin.y + origin.y,
                                                          usedRect.size.width, usedRect.size.height);
                                 }

                                 if (codeFont) {
                                   // Size the chip from the code font's ascent/descent around the
                                   // baseline so the gaps above and below the glyphs are symmetric.
                                   // The line fragment rect extends too far upward because the
                                   // paragraph's extra line height sits above the baseline.
                                   CGFloat baselineY = rect.origin.y +
                                                       [layoutManager locationForGlyphAtIndex:intersect.location].y +
                                                       origin.y;
                                   CGFloat chipTop = baselineY - codeFont.ascender - verticalPadding;
                                   CGFloat chipBottom = baselineY - codeFont.descender + verticalPadding;
                                   finalRect.origin.y = chipTop;
                                   finalRect.size.height = chipBottom - chipTop;
                                 }

                                 [self drawBackgroundAndBorders:finalRect
                                                backgroundColor:backgroundColor
                                                    borderColor:borderColor
                                                        isFirst:isFirst
                                                         isLast:isLast];
                               }];
}

#pragma mark - Drawing Logic

- (void)drawBackgroundAndBorders:(CGRect)rect
                 backgroundColor:(RCTUIColor *)backgroundColor
                     borderColor:(RCTUIColor *)borderColor
                         isFirst:(BOOL)isFirst
                          isLast:(BOOL)isLast
{
  UIBezierPath *path = [self pathForRect:rect isFirst:isFirst isLast:isLast];
  [backgroundColor setFill];
  [path fill];

  if (borderColor) {
    [borderColor setStroke];
    UIBezierPath *strokePath =
        (isFirst && isLast) ? path : [self openBorderPathForRect:rect isFirst:isFirst isLast:isLast];
    strokePath.lineWidth = kCodeBackgroundBorderWidth;
    BezierPathSetRoundStyle(strokePath);
    [strokePath stroke];
  }
}

- (UIBezierPath *)pathForRect:(CGRect)rect isFirst:(BOOL)isFirst isLast:(BOOL)isLast
{
#if !TARGET_OS_OSX
  UIRectCorner corners = 0;
  if (isFirst)
    corners |= (UIRectCornerTopLeft | UIRectCornerBottomLeft);
  if (isLast)
    corners |= (UIRectCornerTopRight | UIRectCornerBottomRight);

  return [UIBezierPath bezierPathWithRoundedRect:rect
                               byRoundingCorners:corners
                                     cornerRadii:CGSizeMake(kCodeBackgroundCornerRadius, kCodeBackgroundCornerRadius)];
#else
  // NSBezierPath doesn't support per-corner rounding — use uniform corner radius
  CGFloat cornerRadius = (isFirst || isLast) ? kCodeBackgroundCornerRadius : 0;
  return UIBezierPathWithRoundedRect(rect, cornerRadius);
#endif
}

- (UIBezierPath *)openBorderPathForRect:(CGRect)rect isFirst:(BOOL)isFirst isLast:(BOOL)isLast
{
  UIBezierPath *path = [UIBezierPath bezierPath];
  CGFloat r = kCodeBackgroundCornerRadius;
  CGFloat inset = kCodeBackgroundBorderWidth / 2.0;
  CGRect insetRect = CGRectInset(rect, inset, inset);

  if (isFirst) {
    [path moveToPoint:CGPointMake(CGRectGetMaxX(rect), insetRect.origin.y)];
    BezierPathAddLine(path, CGPointMake(insetRect.origin.x + r, insetRect.origin.y));
    BezierPathAddQuadCurve(path, CGPointMake(insetRect.origin.x, insetRect.origin.y + r),
                           CGPointMake(insetRect.origin.x, insetRect.origin.y));
    BezierPathAddLine(path, CGPointMake(insetRect.origin.x, CGRectGetMaxY(insetRect) - r));
    BezierPathAddQuadCurve(path, CGPointMake(insetRect.origin.x + r, CGRectGetMaxY(insetRect)),
                           CGPointMake(insetRect.origin.x, CGRectGetMaxY(insetRect)));
    BezierPathAddLine(path, CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(insetRect)));
  } else if (isLast) {
    [path moveToPoint:CGPointMake(rect.origin.x, insetRect.origin.y)];
    BezierPathAddLine(path, CGPointMake(CGRectGetMaxX(insetRect) - r, insetRect.origin.y));
    BezierPathAddQuadCurve(path, CGPointMake(CGRectGetMaxX(insetRect), insetRect.origin.y + r),
                           CGPointMake(CGRectGetMaxX(insetRect), insetRect.origin.y));
    BezierPathAddLine(path, CGPointMake(CGRectGetMaxX(insetRect), CGRectGetMaxY(insetRect) - r));
    BezierPathAddQuadCurve(path, CGPointMake(CGRectGetMaxX(insetRect) - r, CGRectGetMaxY(insetRect)),
                           CGPointMake(CGRectGetMaxX(insetRect), CGRectGetMaxY(insetRect)));
    BezierPathAddLine(path, CGPointMake(rect.origin.x, CGRectGetMaxY(insetRect)));
  } else {
    [path moveToPoint:CGPointMake(rect.origin.x, insetRect.origin.y)];
    BezierPathAddLine(path, CGPointMake(CGRectGetMaxX(rect), insetRect.origin.y));
    [path moveToPoint:CGPointMake(rect.origin.x, CGRectGetMaxY(insetRect))];
    BezierPathAddLine(path, CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(insetRect)));
  }
  return path;
}

@end