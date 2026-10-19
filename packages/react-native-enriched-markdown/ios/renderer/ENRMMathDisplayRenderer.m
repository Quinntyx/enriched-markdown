#import "ENRMMathDisplayRenderer.h"
#import "ENRMMathInlineAttachment.h"
#import "MarkdownASTNode.h"
#import "RenderContext.h"
#import "StyleConfig.h"

#import "ENRMFeatureFlags.h"

#if ENRICHED_MARKDOWN_MATH

static const CGFloat ENRMMathDisplayVerticalMargin = 8.0;

@interface ENRMMathDisplayRenderer ()
- (NSString *)extractLatexFromNode:(MarkdownASTNode *)node;
@end

@implementation ENRMMathDisplayRenderer

- (void)renderNodeContent:(MarkdownASTNode *)node
                     into:(NSMutableAttributedString *)output
                  context:(RenderContext *)context
{
  NSString *latex = [self extractLatexFromNode:node];
  if (latex.length == 0) {
    return;
  }

  NSDictionary *textAttrs = [context getTextAttributes];
  UIFont *currentFont = textAttrs[NSFontAttributeName];
  NSMutableDictionary *displayAttrs = [textAttrs mutableCopy];
  NSMutableParagraphStyle *displayStyle = [displayAttrs[NSParagraphStyleAttributeName] mutableCopy];
  if (!displayStyle) {
    displayStyle = [[NSMutableParagraphStyle alloc] init];
  }
  displayStyle.alignment = NSTextAlignmentCenter;
  displayStyle.paragraphSpacingBefore = ENRMMathDisplayVerticalMargin;
  displayStyle.paragraphSpacing = ENRMMathDisplayVerticalMargin;
  displayStyle.minimumLineHeight = 0;
  displayStyle.maximumLineHeight = 0;
  displayAttrs[NSParagraphStyleAttributeName] = displayStyle;

  if (output.length > 0 && ![output.string hasSuffix:@"\n"]) {
    [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:textAttrs]];
  }

  ENRMMathInlineAttachment *attachment = [[ENRMMathInlineAttachment alloc] init];
  attachment.latex = latex;
  CGFloat displayFontSize = [_config mathFontSize];
  attachment.fontSize =
      displayFontSize > 0 ? displayFontSize : (currentFont ? currentFont.pointSize : [_config paragraphFontSize]);
  attachment.mathTextColor = [_config mathColor];
  attachment.displayMode = YES;
  [context.mathReporters addObject:attachment];

#if TARGET_OS_OSX
  [attachment renderForMacOS];
#endif

  NSMutableAttributedString *attachmentString =
      [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
  if (currentFont) {
    [attachmentString addAttribute:NSFontAttributeName value:currentFont range:NSMakeRange(0, attachmentString.length)];
  }
  [attachmentString addAttribute:NSParagraphStyleAttributeName
                           value:displayStyle
                           range:NSMakeRange(0, attachmentString.length)];
  [output appendAttributedString:attachmentString];
  [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:displayAttrs]];
}

- (NSString *)extractLatexFromNode:(MarkdownASTNode *)node
{
  if (node.content.length > 0) {
    return node.content;
  }

  NSMutableString *buffer = [NSMutableString string];
  for (MarkdownASTNode *child in node.children) {
    if (child.content.length > 0) {
      [buffer appendString:child.content];
    }
  }
  return buffer;
}

@end

#endif
