package com.swmansion.enriched.markdown.gestures

import android.view.View
import android.widget.HorizontalScrollView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import java.lang.reflect.Method

/**
 * The root notifies a scrollable block container through this marker when the
 * blockingGestureTags prop changed, so an attached yielder re-runs its
 * relations (nothing else is needed when nothing is attached yet).
 */
internal interface BlockingGestureYielderHost {
  fun onBlockingGestureTagsChanged()
}

/**
 * Why the handler: the app's root Pan drawer (whose handler tags arrive as the
 * blockingGestureTags prop, see DynamicBlockProps) cancels native touches it
 * activates, so an overflowing table or code block could never scroll
 * horizontally. This binding registers a plain RNGH NativeViewGestureHandler
 * on the block's scroll view with `blocksHandlers` = the drawer tags, making
 * those handlers wait for the scroll to fail: while the block overflows, its
 * own scrolling wins a touch started on it; without overflow no handler may be
 * registered and touches stream to the drawer normally.
 *
 * Handler tags are the negative view tag, RNGestureHandlerRootHelper's
 * convention for native-side helpers, and cannot collide with JS handler tags
 * (positive). RNGH is a peer module rather than a library dependency, so the
 * bridge is resolved reflectively once, the way RNGH itself reaches its
 * optional classes; absent at runtime, every call degrades to a no-op.
 */
internal class BlockingGestureYielder(
  private val scrollView: HorizontalScrollView,
  private val blockingGestureTags: () -> IntArray,
) {
  private var overflowing = false
  private var registered = false
  private var configuredTags: IntArray? = null
  private var handlerTag = 0

  private var gestureHandlerModule: Any? = null
  private var bridgeMissing = false

  fun setOverflowing(overflowing: Boolean) {
    if (this.overflowing == overflowing) return
    this.overflowing = overflowing
    sync()
  }

  // The registry entry survives window detach, so a reattached block must
  // re-register here (onLayout runs after this and re-arms overflow too).
  fun onWindowAttached() {
    sync()
  }

  fun onWindowDetached() {
    drop()
  }

  // An attached handler keeps its relations across re-configuration because
  // configureRelations drops the tag's stale ones first (see the module).
  fun onBlockingGestureTagsChanged() {
    if (!overflowing) return
    sync()
  }

  // One pass re-evaluates every input (overflow, tags, attach, relations) and
  // skips native and reflective work whenever nothing changed.
  private fun sync() {
    if (!overflowing) {
      drop()
      return
    }
    if (!scrollView.isAttachedToWindow) return
    val tags = blockingGestureTags()
    // No blocking gesture at all: with nothing to yield to, a registered
    // handler would only shadow the usual touch dispatch.
    if (tags.isEmpty()) {
      drop()
      return
    }
    if (registered && configuredTags?.contentEquals(tags) == true) return

    val module = gestureHandlerModule() ?: return
    if (!registered) registered = register(module)
    if (!registered) return
    if (configuredTags?.contentEquals(tags) != true) {
      if (bridge.configureRelations(module, handlerTag.toDouble(), relationsMap(tags))) {
        configuredTags = tags
      }
    }
  }

  private fun register(module: Any): Boolean {
    // RNGH resolves handlers by the receiving view's id; native child views are
    // born without one, so mint a tag when RN never assigned it.
    if (scrollView.id == View.NO_ID) scrollView.id = View.generateViewId()
    val tag = -scrollView.id
    if (bridge.createGestureHandler(module, HANDLER_NAME, tag.toDouble(), Arguments.createMap()) &&
      bridge.attachGestureHandler(module, tag.toDouble(), scrollView.id.toDouble(), ACTION_TYPE_NONE.toDouble())
    ) {
      handlerTag = tag
      configuredTags = null
      return true
    }
    // A half-registered handler must not linger in the registry.
    bridge.dropGestureHandler(module, tag.toDouble())
    return false
  }

  private fun drop() {
    if (!registered) return
    val tag = handlerTag
    registered = false
    configuredTags = null
    handlerTag = 0
    gestureHandlerModule()?.let { module -> bridge.dropGestureHandler(module, tag.toDouble()) }
  }

  private fun gestureHandlerModule(): Any? {
    if (bridgeMissing) return null
    gestureHandlerModule?.let { return it }
    val context = scrollView.context as? ReactContext
    if (context == null || !bridge.available) {
      // RNGH absent or the view runs without a ReactContext: the feature is
      // off, permanently for this binding.
      bridgeMissing = true
      return null
    }
    val resolved = bridge.module(context)
    if (resolved == null) {
      // A missing module here means it has not registered yet, which can still
      // happen, so the lookup is retried on the next sync rather than latched.
      return null
    }
    gestureHandlerModule = resolved
    return resolved
  }

  private fun relationsMap(tags: IntArray): ReadableMap =
    Arguments.createMap().apply {
      val array = Arguments.createArray()
      tags.forEach { array.pushInt(it) }
      putArray(KEY_BLOCKS_HANDLERS, array)
    }

  companion object {
    // NativeViewGestureHandler.Factory.name
    private const val HANDLER_NAME = "NativeViewGestureHandler"

    // RNGestureHandlerInteractionManager KEY_BLOCKS_HANDLERS
    private const val KEY_BLOCKS_HANDLERS = "blocksHandlers"

    // GestureHandler.ACTION_TYPE_NONE
    private const val ACTION_TYPE_NONE = 0

    private val bridge = NativeGestureBridge()

    // RNGestureHandlerModule reached through its own public methods; the class
    // is unavailable whenever RNGH is not installed, which turns the feature
    // off. Calls run from the UI thread (mount, layout, window callbacks).
    private class NativeGestureBridge {
      // Kotlin compiles non-null Double parameters to primitives, so reflection
      // lookups need double.class; invoke still takes the boxed value.
      private val doubleType = Double::class.javaPrimitiveType!!

      private val moduleClass: Class<*>? =
        try {
          Class.forName("com.swmansion.gesturehandler.react.RNGestureHandlerModule")
        } catch (_: ClassNotFoundException) {
          null
        }

      private val getNativeModule: Method? =
        methodOrNull(ReactContext::class.java, "getNativeModule", Class::class.java)

      private val createMethod: Method? =
        moduleMethod("createGestureHandler", String::class.java, doubleType, ReadableMap::class.java)

      private val attachMethod: Method? =
        moduleMethod(
          "attachGestureHandler",
          doubleType,
          doubleType,
          doubleType,
        )

      private val configureRelationsMethod: Method? =
        moduleMethod("configureRelations", doubleType, ReadableMap::class.java)

      private val dropMethod: Method? =
        moduleMethod("dropGestureHandler", doubleType)

      private fun moduleMethod(
        name: String,
        vararg parameterTypes: Class<*>,
      ): Method? = methodOrNull(moduleClass, name, *parameterTypes)

      private fun methodOrNull(
        declaringClass: Class<*>?,
        name: String,
        vararg parameterTypes: Class<*>,
      ): Method? =
        try {
          declaringClass?.getMethod(name, *parameterTypes)
        } catch (_: NoSuchMethodException) {
          null
        }

      val available: Boolean =
        moduleClass != null &&
          getNativeModule != null &&
          createMethod != null &&
          attachMethod != null &&
          configureRelationsMethod != null &&
          dropMethod != null

      fun module(context: ReactContext): Any? = getNativeModule?.invoke(context, moduleClass)

      fun createGestureHandler(
        module: Any,
        name: String,
        handlerTag: Double,
        config: ReadableMap,
      ): Boolean = invoke(module, createMethod, name, handlerTag, config)

      fun attachGestureHandler(
        module: Any,
        handlerTag: Double,
        viewTag: Double,
        actionType: Double,
      ): Boolean = invoke(module, attachMethod, handlerTag, viewTag, actionType)

      fun configureRelations(
        module: Any,
        handlerTag: Double,
        relations: ReadableMap,
      ): Boolean = invoke(module, configureRelationsMethod, handlerTag, relations)

      fun dropGestureHandler(
        module: Any,
        handlerTag: Double,
      ): Boolean = invoke(module, dropMethod, handlerTag)

      private fun invoke(
        module: Any,
        method: Method?,
        vararg args: Any?,
      ): Boolean =
        if (method == null) {
          false
        } else {
          runCatching { method.invoke(module, *args) }.isSuccess
        }
    }
  }
}
