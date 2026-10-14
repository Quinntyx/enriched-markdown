package com.swmansion.enriched.markdown.renderer

import android.content.Context
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.style.AlignmentSpan
import com.swmansion.enriched.markdown.parser.MarkdownASTNode
import com.swmansion.enriched.markdown.spans.MathInlineSpan
import com.swmansion.enriched.markdown.utils.text.span.SPAN_FLAGS_EXCLUSIVE_EXCLUSIVE
import io.ratex.RaTeXFontLoader

/**
 * Renders LatexMathDisplay nodes that live inside a text segment (nested in list
 * items, blockquotes, etc). Root-level display math is split out into its own
 * MathContainerView segment and never reaches this renderer.
 */
class MathDisplayRenderer(
  private val config: RendererConfig,
  private val context: Context,
) : NodeRenderer {
  override fun render(
    node: MarkdownASTNode,
    builder: SpannableStringBuilder,
    onLinkPress: ((String) -> Unit)?,
    onLinkLongPress: ((String) -> Unit)?,
    factory: RendererFactory,
  ) {
    RaTeXFontLoader.ensureLoaded(context)

    val latex = extractLatex(node)
    if (latex.isEmpty()) return

    if (builder.isNotEmpty() && builder.last() != '\n') {
      builder.append("\n")
    }

    val mathStyle = config.style.mathStyle
    val start = builder.length
    builder.append("\uFFFC")
    val spanEnd = builder.length

    val span =
      MathInlineSpan(
        context = context,
        latex = latex,
        fontSize = mathStyle.fontSize,
        textColor = mathStyle.color,
        displayMode = true,
        onLatexError = config.onLatexError,
      )
    builder.setSpan(span, start, spanEnd, SPAN_FLAGS_EXCLUSIVE_EXCLUSIVE)
    builder.append("\n")

    val alignment =
      when (mathStyle.textAlign) {
        "left" -> null
        "right" -> Layout.Alignment.ALIGN_OPPOSITE
        else -> Layout.Alignment.ALIGN_CENTER
      }
    if (alignment != null) {
      builder.setSpan(
        AlignmentSpan.Standard(alignment),
        start,
        builder.length,
        SPAN_FLAGS_EXCLUSIVE_EXCLUSIVE,
      )
    }
  }

  private fun extractLatex(node: MarkdownASTNode): String {
    if (node.content.isNotEmpty()) return node.content
    return node.children.joinToString("") { it.content }
  }
}
