package com.swmansion.enriched.markdown.spans

/** Native text and table measurement share this optional math contract. */
interface WidthAwareMathSpan {
  fun setAvailableWidth(width: Int): Boolean

  fun naturalWidth(): Int
}

interface MathSourceSpan {
  val latexSource: String
  val displayMode: Boolean
}
