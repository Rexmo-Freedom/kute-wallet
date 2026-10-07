package com.kutewallet.app

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.os.PersistableBundle
import android.util.Base64
import android.view.WindowManager
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.security.SecureRandom

class MainActivity: FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL = "com.kutewallet.app/passkey_prf"
        /// Post-mortem channel: surfaces ApplicationExitInfo (API 30+)
        /// so Dart can report WHY the previous process died. LMK/OOM
        /// kills and native crashes never reach the Dart crash
        /// handlers, don't show in Crashlytics, and Play vitals only
        /// reports Play-installed + diagnostics-consenting devices —
        /// this is the only signal that works on sideloaded test
        /// builds on low-RAM phones.
        const val EXIT_INFO_CHANNEL = "com.kutewallet.app/exit_info"
        /// `androidx.credentials` exposes WebAuthn PRF as JSON
        /// `extensions.prf.eval.first` (and `.second`). Available on
        /// Android 14+ (API 34) — earlier versions don't surface the
        /// PRF extension through CredentialManager. We report
        /// unsupported below that and let the Dart side fall back to
        /// BIP39.
        const val PRF_MIN_API = Build.VERSION_CODES.UPSIDE_DOWN_CAKE // 34
        /// Capture protection for recovery phrase screens. Dart
        /// (`lib/helpers/secure_screen.dart`) sends
        /// `setSecureScreen(enabled)` when the first such screen mounts
        /// and when the last one goes away, so screenshots and recording
        /// of every other screen stay allowed. `copySensitive(text)` copies
        /// a recovery phrase or private key flagged
        /// `ClipDescription.EXTRA_IS_SENSITIVE`, so the system clipboard
        /// preview and keyboards do not show it.
        const val SECURITY_CHANNEL = "com.kutewallet.app/security"
        /// `ClipDescription.EXTRA_IS_SENSITIVE` is API 33+; the same key
        /// as a string is what Android 12L and earlier OEM previews honour.
        const val LEGACY_EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(OnchainPlugin::class.java)) flutterEngine.plugins.add(OnchainPlugin())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPrfAvailable" -> result.success(Build.VERSION.SDK_INT >= PRF_MIN_API)
                    "registerCredential" -> {
                        if (Build.VERSION.SDK_INT < PRF_MIN_API) {
                            result.error("PRF_UNAVAILABLE",
                                "Passkey PRF requires Android 14 or newer",
                                null)
                            return@setMethodCallHandler
                        }
                        val rpId = call.argument<String>("rpId")
                        val rpName = call.argument<String>("rpName") ?: "Kute Wallet"
                        val userName = call.argument<String>("userName")
                            ?: "kute-wallet-user"
                        val userDisplay = call.argument<String>("userDisplayName")
                            ?: rpName
                        if (rpId.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing rpId", null)
                            return@setMethodCallHandler
                        }
                        registerCredential(rpId, rpName, userName, userDisplay, result)
                    }
                    "derivePrfSeed" -> {
                        if (Build.VERSION.SDK_INT < PRF_MIN_API) {
                            result.error("PRF_UNAVAILABLE",
                                "Passkey PRF requires Android 14 or newer",
                                null)
                            return@setMethodCallHandler
                        }
                        val rpId = call.argument<String>("rpId")
                        val salt = call.argument<String>("salt")
                        if (rpId.isNullOrBlank() || salt == null) {
                            result.error("BAD_ARGS", "Missing rpId or salt", null)
                            return@setMethodCallHandler
                        }
                        // Optional credential allow-list — Dart-side
                        // passes the credential ID we recorded at
                        // registration so the OS pins the assertion
                        // to this specific passkey and skips the
                        // account-picker sheet.
                        @Suppress("UNCHECKED_CAST")
                        val credentialIds = call.argument<List<ByteArray>>("credentialIds")
                            ?: emptyList()
                        derivePrfSeed(rpId, salt, credentialIds, result)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXIT_INFO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLastExitReasons" -> result.success(getLastExitReasons())
                    // Crash context key only (Crashlytics `low_ram`).
                    "isLowRamDevice" -> result.success(
                        try {
                            (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager)
                                .isLowRamDevice
                        } catch (_: Throwable) {
                            null
                        }
                    )
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    "copySensitive" -> {
                        val text = call.argument<String>("text")
                        if (text == null) {
                            result.error("BAD_ARGS", "copySensitive requires text", null)
                            return@setMethodCallHandler
                        }
                        runOnUiThread {
                            try {
                                copySensitive(text)
                                result.success(null)
                            } catch (e: Throwable) {
                                // Dart falls back to a plain copy.
                                result.error("CLIPBOARD_ERROR", e::class.java.simpleName, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun copySensitive(text: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("", text)
        clip.description.extras = PersistableBundle().apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            } else {
                putBoolean(LEGACY_EXTRA_IS_SENSITIVE, true)
            }
        }
        clipboard.setPrimaryClip(clip)
    }

    /// Most recent process-death records for this package, newest
    /// first. Empty below API 30 or on any platform hiccup — the Dart
    /// side treats empty as "nothing to report".
    private fun getLastExitReasons(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            am.getHistoricalProcessExitReasons(packageName, 0, 5).map { info ->
                mapOf(
                    "timestamp" to info.timestamp,
                    "reason" to info.reason,
                    "reasonName" to exitReasonName(info.reason),
                    // RunningAppProcessInfo importance at death —
                    // foreground (100) vs cached tells us whether the
                    // user was actively using the app when it died.
                    "importance" to info.importance,
                    "status" to info.status,
                    "description" to (info.description ?: ""),
                    // Memory footprint at death, in kB, straight from
                    // the kernel record — the smoking gun for LMK.
                    "rssKb" to info.rss,
                    "pssKb" to info.pss,
                )
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun exitReasonName(reason: Int): String = when (reason) {
        android.app.ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        android.app.ApplicationExitInfo.REASON_CRASH -> "crash"
        android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        android.app.ApplicationExitInfo.REASON_ANR -> "anr"
        android.app.ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        android.app.ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        android.app.ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        android.app.ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        android.app.ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        android.app.ApplicationExitInfo.REASON_FREEZER -> "freezer"
        android.app.ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "package_state_change"
        android.app.ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "package_updated"
        android.app.ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        android.app.ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        android.app.ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "unknown_$reason"
    }

    private fun registerCredential(
        rpId: String,
        rpName: String,
        userName: String,
        userDisplayName: String,
        result: MethodChannel.Result
    ) {
        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val userId = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val json = JSONObject().apply {
            put("rp", JSONObject().apply {
                put("id", rpId)
                put("name", rpName)
            })
            put("user", JSONObject().apply {
                put("id", base64UrlEncode(userId))
                put("name", userName)
                put("displayName", userDisplayName)
            })
            put("challenge", base64UrlEncode(challenge))
            put("pubKeyCredParams", org.json.JSONArray().apply {
                put(JSONObject().apply {
                    put("type", "public-key")
                    put("alg", -7) // ES256
                })
                put(JSONObject().apply {
                    put("type", "public-key")
                    put("alg", -257) // RS256
                })
            })
            put("timeout", 60_000)
            put("authenticatorSelection", JSONObject().apply {
                put("authenticatorAttachment", "platform")
                // "preferred", NOT "required". A required resident
                // (discoverable) key crashes registration on OEMs /
                // Android versions with incomplete CredentialManager
                // support (some Samsung / OnePlus / API 33-34 builds)
                // and adds a second ceremony on others. We pin every
                // assertion via `allowCredentials` (the stored
                // credential ID), so a discoverable key is a nicety for
                // first-run-on-a-new-device, not a requirement —
                // "preferred" still creates one where the device can.
                put("residentKey", "preferred")
                put("userVerification", "required")
            })
            put("extensions", JSONObject().apply {
                // `prf` with no `eval` payload is the registration
                // equivalent of iOS's `.checkForSupport` — write the
                // PRF-capable flag into the credential without
                // consuming a salt. Assertions provide the salt.
                put("prf", JSONObject())
            })
        }

        val request = CreatePublicKeyCredentialRequest(
            requestJson = json.toString(),
            preferImmediatelyAvailableCredentials = false
        )

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val cm = CredentialManager.create(this@MainActivity)
                val response = withContext(Dispatchers.IO) {
                    cm.createCredential(this@MainActivity, request)
                }
                if (response is CreatePublicKeyCredentialResponse) {
                    // Parse the rawId out of the registration response
                    // so Dart can persist it and pin future assertions
                    // to this specific credential — skips the OS
                    // account-picker sheet on subsequent sign-ins.
                    val rawId = try {
                        val root = JSONObject(response.registrationResponseJson)
                        val rawIdB64 = root.optString("rawId", "")
                        if (rawIdB64.isNotEmpty()) {
                            android.util.Base64.decode(
                                rawIdB64,
                                android.util.Base64.URL_SAFE or
                                    android.util.Base64.NO_PADDING or
                                    android.util.Base64.NO_WRAP
                            )
                        } else null
                    } catch (_: Throwable) {
                        null
                    }
                    result.success(rawId)
                } else {
                    result.error("PRF_ERROR",
                        "Unexpected credential type",
                        null)
                }
            } catch (e: CreateCredentialCancellationException) {
                // User dismissed the passkey sheet — distinct from a real
                // failure so the Dart side can avoid the BIP39 fallback.
                result.error("USER_CANCELLED", e.message ?: "User cancelled", null)
            } catch (e: CreateCredentialException) {
                result.error("PRF_ERROR", e.message ?: e::class.java.simpleName, null)
            } catch (e: Throwable) {
                // Throwable, NOT Exception. On OEMs missing / shipping a
                // broken CredentialManager provider (observed on older
                // Motorola), createCredential can blow up with an Error
                // (NoClassDefFoundError / NoSuchMethodError) rather than
                // an Exception. Catching only Exception lets those crash
                // the app; catching Throwable routes them back to Dart,
                // which already falls back to a BIP39 wallet.
                result.error("PRF_ERROR", e::class.java.simpleName, null)
            }
        }
    }

    private fun derivePrfSeed(
        rpId: String,
        saltString: String,
        credentialIds: List<ByteArray>,
        result: MethodChannel.Result
    ) {
        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
        // Salt encoding: raw UTF-8 of the Dart-supplied string. The
        // authenticator internally applies WebAuthn's
        // `"WebAuthn PRF" || 0x00 || salt` transformation before
        // HMAC-SHA256, matching iOS/web siblings on the same
        // passkey. Do NOT pre-hash here.
        val saltBytes = saltString.toByteArray(Charsets.UTF_8)
        val json = JSONObject().apply {
            put("rpId", rpId)
            put("challenge", base64UrlEncode(challenge))
            put("timeout", 60_000)
            put("userVerification", "required")
            if (credentialIds.isNotEmpty()) {
                // Pin the assertion to the credential(s) the Dart side
                // told us about — Android's CredentialManager honors
                // `allowCredentials` exactly like the WebAuthn spec,
                // so the platform UI goes straight to the biometric
                // ceremony for this credential without the picker.
                put("allowCredentials", org.json.JSONArray().apply {
                    for (id in credentialIds) {
                        put(JSONObject().apply {
                            put("type", "public-key")
                            put("id", base64UrlEncode(id))
                        })
                    }
                })
            }
            put("extensions", JSONObject().apply {
                put("prf", JSONObject().apply {
                    put("eval", JSONObject().apply {
                        put("first", base64UrlEncode(saltBytes))
                    })
                })
            })
        }

        val option = GetPublicKeyCredentialOption(requestJson = json.toString())
        val request = GetCredentialRequest(credentialOptions = listOf(option))

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val cm = CredentialManager.create(this@MainActivity)
                val response = withContext(Dispatchers.IO) {
                    cm.getCredential(this@MainActivity, request)
                }
                val credential = response.credential
                if (credential !is PublicKeyCredential) {
                    result.error("PRF_ERROR",
                        "Unexpected credential type",
                        null)
                    return@launch
                }
                val prfBytes = extractPrfFromResponse(credential.authenticationResponseJson)
                if (prfBytes == null) {
                    result.error("PRF_UNAVAILABLE",
                        "Credential did not return PRF output",
                        null)
                    return@launch
                }
                if (prfBytes.size != 32) {
                    result.error("PRF_ERROR",
                        "PRF output length ${prfBytes.size} bytes, expected 32",
                        null)
                    return@launch
                }
                // Also surface the rawId of the credential the user
                // picked at the OS sheet. Dart persists it on first
                // sight so subsequent assertions skip the picker.
                val credentialId =
                    extractRawIdFromResponse(credential.authenticationResponseJson)
                val payload = HashMap<String, Any>().apply {
                    put("prf", prfBytes)
                    if (credentialId != null) {
                        put("credentialId", credentialId)
                    }
                }
                result.success(payload)
            } catch (e: GetCredentialCancellationException) {
                result.error("USER_CANCELLED", e.message ?: "User cancelled", null)
            } catch (e: GetCredentialException) {
                result.error("PRF_ERROR", e.message ?: e::class.java.simpleName, null)
            } catch (e: Throwable) {
                // See registerCredential: catch Throwable so a broken /
                // missing OEM credential provider returns an error to
                // Dart instead of crashing the process.
                result.error("PRF_ERROR", e::class.java.simpleName, null)
            }
        }
    }

    /// Pull the 32-byte PRF.first output from the assertion JSON.
    /// `clientExtensionResults.prf.results.first` is base64url-encoded
    /// per the WebAuthn JSON serialization spec.
    private fun extractPrfFromResponse(json: String): ByteArray? {
        return try {
            val root = JSONObject(json)
            val ext = root.optJSONObject("clientExtensionResults") ?: return null
            val prf = ext.optJSONObject("prf") ?: return null
            val results = prf.optJSONObject("results") ?: return null
            val firstB64 = results.optString("first", "")
            if (firstB64.isEmpty()) return null
            base64UrlDecode(firstB64)
        } catch (_: Exception) {
            null
        }
    }

    /// Top-level `rawId` from the assertion JSON — the credential
    /// identifier the user picked at the OS sheet. base64url-encoded
    /// per the WebAuthn JSON spec.
    private fun extractRawIdFromResponse(json: String): ByteArray? {
        return try {
            val root = JSONObject(json)
            val rawIdB64 = root.optString("rawId", "")
            if (rawIdB64.isEmpty()) return null
            base64UrlDecode(rawIdB64)
        } catch (_: Exception) {
            null
        }
    }

    private fun base64UrlEncode(bytes: ByteArray): String =
        Base64.encodeToString(bytes,
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    private fun base64UrlDecode(s: String): ByteArray =
        Base64.decode(s, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
}
