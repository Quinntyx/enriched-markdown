#include "MD4CParser.hpp"
#include <cassert>
#include <iostream>
#include <string>

using Markdown::MarkdownASTNode;
using Markdown::NodeType;

static size_t count(const std::shared_ptr<MarkdownASTNode> &node, NodeType type) {
  size_t result = node->type == type;
  for (const auto &child : node->children)
    result += count(child, type);
  return result;
}

static std::string plainText(const std::shared_ptr<MarkdownASTNode> &node) {
  auto text = node->content;
  for (const auto &child : node->children)
    text += plainText(child);
  return text;
}

int main() {
  Markdown::MD4CParser parser;
  for (const auto &eol : {std::string("\n"), std::string("\r\n"), std::string("\r")}) {
    const auto source = "$$" + eol + "\\alpha% comment" + eol + "x" + eol + "$$";
    auto root = parser.parse(source);
    assert(count(root, NodeType::LatexMathDisplay) == 1);
    assert(plainText(root).find("\\alpha% comment\nx") != std::string::npos);
  }
  for (const auto &source :
       {R"(Price $5-$10 and $5 and $10.)", R"(Reference \[1\] and \[1, 2\].)", R"(`$x$` and `\[x\]`)", "    \\(x\\)"}) {
    auto root = parser.parse(source);
    assert(count(root, NodeType::LatexMathInline) == 0);
    assert(count(root, NodeType::LatexMathDisplay) == 0);
  }
  for (const auto &source : {"```math\nx+y\n```", "~~~math\nx+y\n~~~", "> ```math\n> x+y\n> ```"}) {
    auto root = parser.parse(source);
    assert(count(root, NodeType::LatexMathDisplay) == 1);
    assert(count(root, NodeType::CodeBlock) == 0);
  }
  for (const auto &source : {"```math\nx+y", "$$\nx+y\n", "\\[\nx+y\n"}) {
    auto root = parser.parse(source);
    assert(count(root, NodeType::LatexMathDisplay) == 0);
  }
  Markdown::Md4cFlags disabled;
  disabled.latexMath = false;
  assert(count(parser.parse("```math\nx+y\n```", disabled), NodeType::CodeBlock) == 1);
  auto inlineMath = parser.parse(R"(Before \(\frac{a}{b}\) after.)");
  assert(count(inlineMath, NodeType::LatexMathInline) == 1);
  for (const auto &source : {std::string("\\[\n\\begin{aligned}\nx &= 1 \\\\\n-b &= 2\n\\end{aligned}\n\\]"),
                             std::string("$$\nx\n---\ny\n$$"), std::string("- \\[\nx = 1\n-b = 2\n\\]"),
                             std::string("> \\[\n> x = 1\n> -b = 2\n> \\]")}) {
    auto root = parser.parse(source);
    if (count(root, NodeType::LatexMathDisplay) != 1)
      std::cerr << source << '\n';
    assert(count(root, NodeType::LatexMathDisplay) == 1);
    assert(count(root, NodeType::ThematicBreak) == 0);
    assert(count(root, NodeType::CodeBlock) == 0);
  }
  assert(count(parser.parse(R"(`\(x\)` and `$$y$$`)"), NodeType::LatexMathInline) == 0);
  assert(count(parser.parse(R"(\[unfinished)"), NodeType::LatexMathDisplay) == 0);
  for (const auto &source : {R"(Before $$x^2$$ after.)", R"(Before \[x^2\] after.)"}) {
    auto root = parser.parse(source);
    assert(root->children.size() == 3);
    assert(root->children[0]->type == NodeType::Paragraph);
    assert(root->children[1]->type == NodeType::LatexMathDisplay);
    assert(root->children[2]->type == NodeType::Paragraph);
  }
  auto inlineDollar = parser.parse("Before $x^2$ after.");
  assert(inlineDollar->children.size() == 1);
  assert(count(inlineDollar, NodeType::LatexMathInline) == 1);
  auto table = parser.parse(
      "| Formula | Notes |\n| --- | --- |\n| $|x|$ | Norm |\n| \\(\\|y\\|\\) | Other |\n| $$a+b$$ | Display |\n");
  assert(count(table, NodeType::TableCell) == 6);
  assert(count(table, NodeType::LatexMathInline) == 2);
  assert(count(table, NodeType::LatexMathDisplay) == 1);
  assert(plainText(table).find("\\|y\\|") != std::string::npos);
  auto linkedTable = parser.parse("| [a](https://example.com/$x) | y$ |\n| --- | --- |");
  assert(count(linkedTable, NodeType::TableHeaderCell) == 2);
  assert(count(linkedTable, NodeType::Link) == 1);
  assert(count(linkedTable, NodeType::LatexMathInline) == 0);
  auto breaks = parser.parse("| Value |\n| --- |\n| A<br>B<br/>C<br />D |\n");
  assert(count(breaks, NodeType::LineBreak) == 3);
  auto nested = parser.parse("- Before $$x$$ after.\n\n> Before $$y$$ after.");
  assert(count(nested, NodeType::LatexMathDisplay) == 2);
  assert(count(parser.parse("++marked++ and [^note]\n\n[^note]: footnote"), NodeType::LatexMathInline) == 0);
  std::cout << "Native math parser regressions passed\n";
}
