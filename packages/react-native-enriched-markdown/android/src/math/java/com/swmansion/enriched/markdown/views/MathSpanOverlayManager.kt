package com.swmansion.enriched.markdown.views

import android.graphics.Rect
import android.text.Spanned
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.swmansion.enriched.markdown.accessibility.AccessibilityLabels
import com.swmansion.enriched.markdown.segments.DynamicBlockProps
import com.swmansion.enriched.markdown.segments.MathContainerView
import com.swmansion.enriched.markdown.segments.TableContainerView
import com.swmansion.enriched.markdown.spans.MathInlineSpan
import com.swmansion.enriched.markdown.styles.StyleConfig

/**
 * T3 Chat's native scroll-view overlays, adapted to the current Enriched fork.
 * Inline formulas keep their original font and display mode. Table cells retain
 * their natural width and scroll with their table instead of receiving overlays.
 * Keys survive vertical reflow during streaming so scroll positions stay intact.
 */
class MathSpanOverlayManager(
  private val container: ViewGroup,
) {
  private val overlaysByKey = HashMap<String, MathContainerView>()

  private fun textViews(view: View): List<TextView> =
    when (view) {
      is TableContainerView, is MathContainerView -> emptyList()
      is TextView -> listOf(view)
      is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
      else -> emptyList()
    }

  fun update(
    style: StyleConfig,
    dynamicProps: DynamicBlockProps,
    accessibilityLabels: AccessibilityLabels,
  ) {
    val desiredKeys = HashSet<String>()
    var occurrence = 0
    for (textView in textViews(container)) {
      val spanned = textView.text as? Spanned ?: continue
      val layout = textView.layout ?: continue
      var spansChanged = false
      val spans =
        spanned
          .getSpans(0, spanned.length, MathInlineSpan::class.java)
          .sortedBy { spanned.getSpanStart(it) }
      for (span in spans) {
        val index = occurrence++
        val start = spanned.getSpanStart(span)
        if (start < 0) continue
        val line = layout.getLineForOffset(start)
        val paragraphLeft = layout.getParagraphLeft(line)
        val paragraphRight = layout.getParagraphRight(line)
        val availableWidth = paragraphRight - paragraphLeft
        val overflows = availableWidth > 0 && span.naturalWidth() > availableWidth
        if (span.overflowsLine != overflows) {
          span.overflowsLine = overflows
          spansChanged = true
        }
        if (!overflows) continue
        val key = "$index|${span.latex}|${span.displayMode}|${span.fontSize}|${span.textColor}"
        desiredKeys += key
        val overlay =
          overlaysByKey.getOrPut(key) {
            MathContainerView(container.context, style, inlineOverlay = true).also {
              it.applyLatex(span.latex, span.displayMode, span.fontSize, span.textColor)
              container.addView(it, ViewGroup.LayoutParams(availableWidth, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
          }
        overlay.dynamicProps = dynamicProps
        overlay.accessibilityLabels = accessibilityLabels
        val origin = Rect(0, 0, 0, 0)
        container.offsetDescendantRectToMyCoords(textView, origin)
        val lineLeft = origin.left + textView.totalPaddingLeft + paragraphLeft
        val lineTop = origin.top + textView.totalPaddingTop + layout.getLineTop(line)
        val lineBottom = origin.top + textView.totalPaddingTop + layout.getLineBottom(line)
        overlay.measure(
          View.MeasureSpec.makeMeasureSpec(availableWidth, View.MeasureSpec.EXACTLY),
          View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val overlayTop = lineTop + ((lineBottom - lineTop) - overlay.measuredHeight) / 2
        overlay.layout(lineLeft, overlayTop, lineLeft + availableWidth, overlayTop + overlay.measuredHeight)
      }
      if (spansChanged) textView.invalidate()
    }
    val staleKeys = overlaysByKey.keys.filter { it !in desiredKeys }
    for (key in staleKeys) overlaysByKey.remove(key)?.let { container.removeView(it) }
  }

  fun removeAllOverlays() {
    for (overlay in overlaysByKey.values) container.removeView(overlay)
    overlaysByKey.clear()
  }
}
