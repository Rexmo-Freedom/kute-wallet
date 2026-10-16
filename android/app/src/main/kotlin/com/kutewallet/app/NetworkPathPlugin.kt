package com.kutewallet.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Bridges the Dart `kute/network_path` EventChannel
 * (`lib/services/network_change_signal.dart`): one `"changed"` event each
 * time the app's default network changes, so the app asks every region
 * answer again (Polymarket's geoblock, Hyperliquid's legal check, Kute's
 * policy) instead of keeping the one it got on the old network.
 *
 *  - `ConnectivityManager.registerDefaultNetworkCallback` watches the
 *    app's default network, which "may be a physical network or a virtual
 *    network, such as a VPN that applies to the application" (the API's
 *    own words): a VPN coming up or going down replaces the default
 *    network like a Wi-Fi to mobile switch does;
 *  - the first answer after registering is the baseline, not a change;
 *  - callbacks that leave the network's shape alone (the network, its
 *    transports, its interface, addresses and DNS) are dropped here, so
 *    bandwidth and signal updates never reach Dart. Dart debounces the
 *    rest;
 *  - the event carries no detail: no interface names, no addresses.
 *
 * Needs `ACCESS_NETWORK_STATE` (a normal permission, no prompt). Every
 * platform call is guarded: a phone that refuses the callback simply sends
 * nothing, and the app falls back to re-checking on resume and at the tap.
 */
class NetworkPathPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private var channel: EventChannel? = null
    private var context: Context? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    /** Touched from the connectivity callback thread only (and reset on start). */
    @Volatile
    private var lastSignature: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = EventChannel(binding.binaryMessenger, CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        sink = null
        channel?.setStreamHandler(null)
        channel = null
        context = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    private fun connectivity(): ConnectivityManager? = try {
        context?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    } catch (e: Throwable) {
        null
    }

    private fun start() {
        stop()
        val manager = connectivity() ?: return
        lastSignature = null
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report(manager, network)
            override fun onLost(network: Network) = report(manager, null)
            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) = report(manager, network)

            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: LinkProperties,
            ) = report(manager, network)
        }
        try {
            manager.registerDefaultNetworkCallback(cb)
            callback = cb
        } catch (e: Throwable) {
            callback = null
        }
    }

    private fun stop() {
        val cb = callback ?: return
        callback = null
        try {
            connectivity()?.unregisterNetworkCallback(cb)
        } catch (e: Throwable) {
            // Already unregistered or the service is gone: nothing to stop.
        }
    }

    private fun report(manager: ConnectivityManager, network: Network?) {
        try {
            val signature = signature(manager, network)
            val previous = lastSignature
            lastSignature = signature
            if (previous == null || previous == signature) return
            main.post {
                try {
                    sink?.success("changed")
                } catch (e: Throwable) {
                    // The Dart side went away between the change and the post.
                }
            }
        } catch (e: Throwable) {
            // A network the system no longer describes: the next callback reports.
        }
    }

    /** What a VPN, a Wi-Fi join or a SIM swap changes. Kept on the device. */
    private fun signature(manager: ConnectivityManager, network: Network?): String {
        if (network == null) return "none"
        val caps = manager.getNetworkCapabilities(network)
        val transports = TRANSPORTS.filter { caps?.hasTransport(it) == true }
        val link = manager.getLinkProperties(network)
        return listOf(
            network.toString(),
            transports.joinToString(","),
            link?.interfaceName ?: "",
            link?.linkAddresses?.joinToString(",") ?: "",
            link?.dnsServers?.joinToString(",") ?: "",
        ).joinToString("|")
    }

    companion object {
        private const val CHANNEL = "kute/network_path"
        private val TRANSPORTS = listOf(
            NetworkCapabilities.TRANSPORT_CELLULAR,
            NetworkCapabilities.TRANSPORT_WIFI,
            NetworkCapabilities.TRANSPORT_ETHERNET,
            NetworkCapabilities.TRANSPORT_VPN,
        )
    }
}
