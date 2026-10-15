package com.swmansion.enriched.markdown.segments

import android.graphics.Color
import android.view.View.MeasureSpec
import com.facebook.react.bridge.JavaOnlyMap
import com.facebook.react.uimanager.DisplayMetricsHolder
import com.swmansion.enriched.markdown.keepsCodeBlockWrapState
import com.swmansion.enriched.markdown.parser.MarkdownASTNode
import com.swmansion.enriched.markdown.parser.MarkdownASTNode.NodeType
import com.swmansion.enriched.markdown.styles.StyleConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CodeBlockContainerViewTest {
  private val context = RuntimeEnvironment.getApplication()

  @Test
  fun measuredHeightMatchesTheLaidOutViewWrappedAndUnwrapped() {
    val config = styleConfig()
    val line = "val values = listOf(" + (1..60).joinToString(", ") { "item$it" } + ")"
    val node =
      MarkdownASTNode(
        NodeType.CodeBlock,
        attributes = mapOf("fenceChar" to "`", "language" to "kotlin"),
        children = listOf(MarkdownASTNode(NodeType.Text, "$line\n")),
      )

    for (width in listOf(240, 360, 600)) {
      val view = CodeBlockContainerView(context, config).apply { applyCodeBlockNode(node) }

      fun measure(wrapped: Boolean): Int {
        view.wrapped = wrapped
        view.measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        return view.measuredHeight
      }

      val unwrapped = measure(false)
      assertEquals(
        "unwrapped at width $width",
        CodeBlockContainerView.measureCodeBlockNodeHeight(node, config, context, width.toFloat(), false),
        unwrapped.toFloat(),
        0f,
      )
      val wrapped = measure(true)
      assertEquals(
        "wrapped at width $width",
        CodeBlockContainerView.measureCodeBlockNodeHeight(node, config, context, width.toFloat(), true),
        wrapped.toFloat(),
        0f,
      )
      assertTrue("wrapped $wrapped should be taller than unwrapped $unwrapped at width $width", wrapped > unwrapped)
    }
  }

  @Test
  fun wrapStateSurvivesOnlyInPlaceGrowth() {
    val block = "```kotlin\nval a = 1\n```\n"
    assertTrue("streaming append", keepsCodeBlockWrapState("Intro\n\n```kotlin\nval a", "Intro\n\n$block"))
    assertTrue("identical markdown", keepsCodeBlockWrapState("Intro\n\n$block", "Intro\n\n$block"))
    assertTrue("unfinished last line rewritten", keepsCodeBlockWrapState("$block\nSee <summ", "$block\nSee \n\n**Details**"))
    assertFalse("replaced document", keepsCodeBlockWrapState("Intro\n\n$block", "Other\n\n$block"))
    assertFalse("block inserted above", keepsCodeBlockWrapState("Intro\n\n$block", "Intro\n\n```\nnew\n```\n\n$block"))
  }

  private fun styleConfig(): StyleConfig {
    DisplayMetricsHolder.initDisplayMetricsIfNotInitialized(context)
    val codeBlock =
      JavaOnlyMap.of(
        "fontSize",
        14.0,
        "fontFamily",
        "monospace",
        "fontWeight",
        "",
        "color",
        Color.WHITE,
        "lineHeight",
        22.0,
        "marginTop",
        0.0,
        "marginBottom",
        16.0,
        "backgroundColor",
        Color.DKGRAY,
        "borderColor",
        Color.GRAY,
        "borderRadius",
        8.0,
        "borderWidth",
        1.0,
        "padding",
        16.0,
      )
    return StyleConfig(JavaOnlyMap.of("codeBlock", codeBlock), context, false, 0f)
  }
}
