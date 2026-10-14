#import "../../ios/utils/ENRMTextViewSetup.h"
#import <XCTest/XCTest.h>

@interface ENRMIntrinsicWidthTests : XCTestCase
@end

@implementation ENRMIntrinsicWidthTests

- (CGSize)measurePlainText:(NSString *)string maxWidth:(CGFloat)maxWidth
{
  NSTextStorage *storage = [[NSTextStorage alloc] initWithString:string
                                                      attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:16]}];
  NSLayoutManager *manager = [[NSLayoutManager alloc] init];
  NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)];
  container.lineFragmentPadding = 0;
  [manager addTextContainer:container];
  [storage addLayoutManager:manager];
  [manager ensureLayoutForTextContainer:container];
  ENRMTextLayoutResult layout = {[manager usedRectForTextContainer:container], manager.extraLineFragmentRect};
  return ENRMFinalizeMeasuredTextSize(layout, manager, storage, maxWidth, nil, NO, 0, YES, 1);
}

- (void)testSingleLineKeepsItsIntrinsicWidth
{
  XCTAssertLessThan([self measurePlainText:@"short" maxWidth:300].width, 300);
}

- (void)testExplicitLineBreaksKeepTheirIntrinsicWidth
{
  for (NSString *separator in @[ @"\n", @"\r", @"\r\n", @"\u2028", @"\u2029" ]) {
    NSString *text = [NSString stringWithFormat:@"one%@two", separator];
    XCTAssertLessThan([self measurePlainText:text maxWidth:300].width, 300, @"%@", text);
  }
}

- (void)testTrailingNewlineKeepsItsIntrinsicWidth
{
  XCTAssertLessThan([self measurePlainText:@"short\n" maxWidth:300].width, 300);
}

- (void)testSoftWrappingKeepsTheAvailableWidth
{
  XCTAssertEqual([self measurePlainText:@"one two three four five six seven eight nine ten" maxWidth:80].width, 80);
}

- (void)testSoftWrappingAfterAnExplicitBreakKeepsTheAvailableWidth
{
  XCTAssertEqual([self measurePlainText:@"one\ntwo three four five six seven eight nine ten" maxWidth:80].width, 80);
}

- (void)testEmojiBeforeAnExplicitBreakKeepsItsIntrinsicWidth
{
  XCTAssertLessThan([self measurePlainText:@"\U0001F600\nshort" maxWidth:300].width, 300);
}

@end
