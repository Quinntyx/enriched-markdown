package com.swmansion.enriched.markdown

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.util.TypedValue
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.swmansion.enriched.markdown.spans.registerWithSpans
import com.swmansion.enriched.markdown.test.MarkdownRenderTestSupport
import com.swmansion.enriched.markdown.test.MarkdownRenderTestSupport.render
import com.swmansion.enriched.markdown.test.TestAstFactory.document
import com.swmansion.enriched.markdown.test.TestAstFactory.image
import com.swmansion.enriched.markdown.test.TestAstFactory.paragraph
import com.swmansion.enriched.markdown.test.TestAstFactory.text
import com.swmansion.enriched.markdown.utils.text.ImageCache
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(AndroidJUnit4::class)
@Config(sdk = [28])
// Legacy graphics report zero font metrics, so the cap height this checks against would be zero.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class InlineImagePlacementTest {
  private val context: Context = ApplicationProvider.getApplicationContext()

  // iOS centers an inline attachment on the font's cap height; Android used to sit the image on
  // the baseline, so an icon taller than the capitals stood above the text.
  @Test
  fun anInlineImageIsCenteredOnTheCapHeight() {
    val url = "test://inline-image-placement"
    ImageCache.putOriginal(url, Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) })
    val style = MarkdownRenderTestSupport.defaultStyle
    val rendered = render(document(paragraph(text("Inline "), image(url), text(" image"))), style)
    val textView = TextView(context)
    textView.setTextSize(TypedValue.COMPLEX_UNIT_PX, style.paragraphStyle.fontSize)
    textView.text = rendered
    textView.registerWithSpans(rendered)
    textView.measure(
      View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
    )
    textView.layout(0, 0, 400, textView.measuredHeight)
    val layout = requireNotNull(textView.layout)

    val bitmap = Bitmap.createBitmap(400, textView.height, Bitmap.Config.ARGB_8888)
    layout.draw(Canvas(bitmap))
    val redRows =
      (0 until bitmap.height).filter { y ->
        (0 until bitmap.width).any { x ->
          val pixel = bitmap.getPixel(x, y)
          Color.alpha(pixel) > 0 && Color.red(pixel) > 128 && Color.green(pixel) < 64
        }
      }
    val imageCenter = (redRows.first() + redRows.last() + 1) / 2f

    val capBounds = Rect()
    textView.paint.getTextBounds("H", 0, 1, capBounds)
    val capCenter = layout.getLineBaseline(0) - capBounds.height() / 2f
    assertEquals(capCenter, imageCenter, 1f)
  }
}
