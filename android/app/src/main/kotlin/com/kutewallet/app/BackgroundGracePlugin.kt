package com.kutewallet.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart `kute/background_grace` MethodChannel
 * (`lib/services/platform/background_grace.dart`): a short stay of
 * execution for a bet or trade still being placed when the person leaves
 * the app.
 *
 * `hold(id, reason)` registers a token, `release(id)` drops it. While any
 * token is held and the activity is paused, a PARTIAL_WAKE_LOCK keeps the
 * CPU awake for Dart for [GRACE_MS] (about 30 seconds, the system times
 * it out); it is released when the activity resumes or the last token
 * goes, and armed again on the next pause while a token lives. Tokens do
 * not expire here: Dart's own watchdog bounds a hold.
 *
 * Honest limits: this is a wake lock, not a foreground service. It does
 * not stop the low-memory killer, the cached-app freezer or an OEM's
 * battery policy (Xiaomi, Huawei, Samsung "sleeping apps") from freezing
 * or killing the process; how long a just-backgrounded process keeps
 * running varies by vendor. A foreground service was judged too heavy for
 * a 30-second wait (its notification, its Play declarations). The
 * WAKE_LOCK permission is a normal one (declared in the manifest, also
 * merged from firebase_messaging).
 */
class BackgroundGracePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        const val CHANNEL = "kute/background_grace"
        /** How long the CPU is kept awake after a pause, per trip. */
        const val GRACE_MS = 30_000L
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var application: Application? = null
    private val held = LinkedHashMap<Int, String>()
    private var lock: PowerManager.WakeLock? = null
    private var paused = false

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityPaused(a: Activity) {
            if (a !== activity) return
            paused = true
            if (held.isNotEmpty()) arm()
        }

        override fun onActivityResumed(a: Activity) {
            if (a !== activity) return
            paused = false
            disarm()
        }

        override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivityStopped(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        held.clear()
        disarm()
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        application = binding.activity.application.also {
            it.registerActivityLifecycleCallbacks(lifecycle)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        application?.unregisterActivityLifecycleCallbacks(lifecycle)
        application = null
        activity = null
        paused = false
        disarm()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hold" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("BAD_ARGS", "hold needs an id", null)
                    return
                }
                held[id] = call.argument<String>("reason") ?: "order"
                // Held while already away (a state change that ran in the
                // background): the window starts now.
                if (paused) arm()
                result.success(true)
            }
            "release" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("BAD_ARGS", "release needs an id", null)
                    return
                }
                held.remove(id)
                if (held.isEmpty()) disarm()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Keeps the CPU awake for [GRACE_MS]; a second arm restarts the clock. */
    private fun arm() {
        val ctx = context ?: return
        try {
            val lock = this.lock ?: run {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kute:grace").also {
                    it.setReferenceCounted(false)
                    this.lock = it
                }
            }
            lock.acquire(GRACE_MS)
        } catch (_: Throwable) {
            // No wake lock: the process gets whatever the OS gives it.
        }
    }

    private fun disarm() {
        try {
            lock?.takeIf { it.isHeld }?.release()
        } catch (_: Throwable) {
            // Already timed out.
        }
    }
}
