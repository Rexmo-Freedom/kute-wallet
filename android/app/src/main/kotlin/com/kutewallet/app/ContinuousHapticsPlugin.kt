package com.kutewallet.app

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Bridges the Dart `kute/continuous_haptics` MethodChannel
 * (`lib/services/continuous_haptics.dart`): the rubber band's felt pull,
 * modelled on Instagram's vanish-mode pull.
 *
 * With amplitude control:
 *  - `start(intensity, sharpness)`: a repeating one-segment waveform (the
 *    rumble) at the intensity's amplitude;
 *  - `update(intensity, sharpness)`: re-issues the waveform at the new
 *    amplitude when it moved by a felt step (a new waveform replaces the
 *    old one in place, with no gap you can feel). Dart sends ~30 a second;
 *  - `tick(intensity, sharpness)`: a ratchet click. Android plays one
 *    vibration at a time, so the click is the head of a new waveform whose
 *    tail repeats the rumble: [click, rumble...];
 *  - `pulse(intensity)`: a one-shot heartbeat beat;
 *  - `pattern(timings, amplitudes)`: one of the app's named patterns
 *    (`lib/services/haptic_patterns.dart`), the waveform Dart rendered from
 *    the same events Core Haptics plays; a wanted rumble resumes after it.
 *    Answers whether it played.
 *
 * Without amplitude control the rumble cannot be shaped, so it is not
 * played: the ratchet's clicks and the heartbeat are plain pulses, and a
 * pattern answers false (Dart plays today's system impacts instead).
 *
 * Every other method answers null and never fails. VIBRATE is declared in the
 * app's manifest (and merged from the `vibration` package). Usage is
 * touch feedback, so the system's haptics setting applies. [stopAll] runs
 * from MainActivity.onPause: nothing buzzes once the app leaves the front.
 */
class ContinuousHapticsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        @Volatile
        private var active: ContinuousHapticsPlugin? = null

        /** Stops the rumble, wherever it plays (the app went to the background). */
        fun stopAll() {
            active?.stopRumble()
        }

        /** One rumble segment; the waveform repeats it. */
        private const val SEGMENT_MS = 1000L
    }

    private var channel: MethodChannel? = null
    private var vibrator: Vibrator? = null
    private var amplitude = false

    /** Dart wants the rumble, at this amplitude. */
    private var wantRumble = false
    private var rumbleAmp = 0
    private var issuedAmp = 0

    /** A click's head plays until then (uptime ms): no update cuts it. */
    private var clickUntil = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vibrator = findVibrator(binding.applicationContext)
        amplitude = try {
            vibrator?.let { it.hasVibrator() && it.hasAmplitudeControl() } ?: false
        } catch (_: Throwable) {
            false
        }
        channel = MethodChannel(binding.binaryMessenger, "kute/continuous_haptics")
            .also { it.setMethodCallHandler(this) }
        active = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopRumble()
        channel?.setMethodCallHandler(null)
        channel = null
        if (active === this) active = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val i = unit(call.argument<Double>("intensity"))
        val s = unit(call.argument<Double>("sharpness"))
        try {
            when (call.method) {
                "start" -> {
                    wantRumble = true
                    rumbleAmp = rumbleAmplitude(i)
                    if (amplitude) playRumble()
                }
                "update" -> {
                    if (wantRumble) {
                        rumbleAmp = rumbleAmplitude(i)
                        if (amplitude &&
                            abs(rumbleAmp - issuedAmp) >= 4 &&
                            SystemClock.uptimeMillis() >= clickUntil
                        ) {
                            playRumble()
                        }
                    }
                }
                "stop" -> stopRumble()
                "tick" -> click(i, s)
                "pulse" -> {
                    val amp = if (amplitude) (40 + 110 * i).roundToInt() else VibrationEffect.DEFAULT_AMPLITUDE
                    vibrate(VibrationEffect.createOneShot(30, amp))
                }
                "pattern" -> {
                    // Answers whether it played: Dart falls back to the
                    // system impacts when it did not.
                    result.success(pattern(call))
                    return
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
        } catch (_: Throwable) {
            // Haptics are never worth a failure.
        }
        result.success(null)
    }

    fun stopRumble() {
        val was = wantRumble || issuedAmp > 0
        wantRumble = false
        rumbleAmp = 0
        issuedAmp = 0
        clickUntil = 0
        if (was) {
            try {
                vibrator?.cancel()
            } catch (_: Throwable) {
            }
        }
    }

    private fun playRumble() {
        if (rumbleAmp <= 0) return
        issuedAmp = rumbleAmp
        vibrate(VibrationEffect.createWaveform(longArrayOf(SEGMENT_MS), intArrayOf(rumbleAmp), 0))
    }

    /** One ratchet click: sharper is shorter (10..18 ms), stronger is harder. */
    private fun click(i: Float, s: Float) {
        val ms = (18 - 8 * s).roundToInt().toLong()
        if (!amplitude) {
            vibrate(VibrationEffect.createOneShot(ms + 4, VibrationEffect.DEFAULT_AMPLITUDE))
            return
        }
        val amp = (80 + 175 * i).roundToInt().coerceIn(1, 255)
        if (wantRumble && rumbleAmp > 0) {
            issuedAmp = rumbleAmp
            clickUntil = SystemClock.uptimeMillis() + ms
            vibrate(
                VibrationEffect.createWaveform(
                    longArrayOf(ms, SEGMENT_MS), intArrayOf(amp, rumbleAmp), 1
                )
            )
        } else {
            vibrate(VibrationEffect.createOneShot(ms, amp))
        }
    }

    /**
     * One of the app's named patterns, as the waveform Dart rendered from
     * its events (`timings` ms, `amplitudes` 0..255). Needs amplitude
     * control (else false: Dart plays the system impacts). A rumble still
     * wanted picks up again after it, as the waveform's repeating tail.
     */
    private fun pattern(call: MethodCall): Boolean {
        if (!amplitude || vibrator == null) return false
        val timings = (call.argument<List<Number>>("timings") ?: return false)
            .map { it.toLong().coerceAtLeast(0) }
        val amps = (call.argument<List<Number>>("amplitudes") ?: return false)
            .map { it.toInt().coerceIn(0, 255) }
        if (timings.isEmpty() || timings.size != amps.size || timings.sum() <= 0) return false
        return try {
            if (wantRumble && rumbleAmp > 0) {
                issuedAmp = rumbleAmp
                clickUntil = SystemClock.uptimeMillis() + timings.sum()
                vibrate(
                    VibrationEffect.createWaveform(
                        (timings + SEGMENT_MS).toLongArray(),
                        (amps + rumbleAmp).toIntArray(),
                        timings.size
                    )
                )
            } else {
                vibrate(
                    VibrationEffect.createWaveform(timings.toLongArray(), amps.toIntArray(), -1)
                )
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun vibrate(effect: VibrationEffect) {
        val v = vibrator ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(
                    effect,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        } catch (_: Throwable) {
        }
    }

    private fun rumbleAmplitude(i: Float): Int = (40 + 160 * i).roundToInt().coerceIn(1, 255)

    private fun unit(v: Double?): Float {
        if (v == null || v.isNaN() || v.isInfinite()) return 0.5f
        return v.toFloat().coerceIn(0f, 1f)
    }

    private fun findVibrator(context: Context): Vibrator? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    } catch (_: Throwable) {
        null
    }
}
