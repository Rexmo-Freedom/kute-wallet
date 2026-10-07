import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// Route classification must match the backend. Venue-to-venue funding needs
/// permission to leave the source and add funds to the destination; a route
/// with a venue leg answers to the venue capabilities ALONE and never to the
/// swap gates below, so a country blocked from swapping can still fund and
/// drain Investing and Predictions.
///
/// Every other route is a cross-chain swap and needs `orchestra.swap` (the
/// master switch) AND its class: `orchestra.swap.stablecoins` when the legs
/// are bitcoin, USDC or USDT, `orchestra.swap.altcoins` when either leg is
/// anything else. A move between the person's own bitcoin rails, or of the
/// dollar balance (USDB), answers to the master alone.
List<String> orchestraCapabilityRequirements({
  required String sourceChain,
  required String sourceAsset,
  required String destinationChain,
  required String destinationAsset,
}) {
  final source = sourceChain.trim().toLowerCase();
  final destination = destinationChain.trim().toLowerCase();
  final caps = <String>[
    if (source == 'hypercore') 'hyperliquid.withdraw',
    if (source == 'polygon' && sourceAsset.toUpperCase() == 'USDC.E')
      'polymarket.withdraw',
    if (destination == 'hypercore') 'hyperliquid.deposit',
    if (destination == 'polygon' && destinationAsset.toUpperCase() == 'USDC.E')
      'polymarket.deposit',
  ];
  if (caps.isNotEmpty) return caps;
  return [
    'orchestra.swap',
    if (orchestraSwapClassCapability(sourceAsset, destinationAsset)
        case final gate?)
      gate,
  ];
}

/// The class gate a non-venue route needs on top of `orchestra.swap`, or
/// null for a route the master switch alone governs (bitcoin to bitcoin,
/// or either leg the dollar balance).
String? orchestraSwapClassCapability(
    String sourceAsset, String destinationAsset) {
  final legs = [
    sourceAsset.trim().toUpperCase(),
    destinationAsset.trim().toUpperCase(),
  ];
  if (legs.contains('USDB')) return null;
  var stable = false;
  for (final asset in legs) {
    switch (asset) {
      case 'BTC':
        break;
      case 'USDC':
      case 'USDT':
        stable = true;
      default:
        return 'orchestra.swap.altcoins';
    }
  }
  return stable ? 'orchestra.swap.stablecoins' : null;
}

/// The gates a deposit address for another network needs, exactly as the
/// backend's operation guard asks them of
/// `POST /api/v1/orchestra/accumulation-addresses`: `crypto.deposit`
/// first, then the route from [sourceChain]/[sourceAsset] into
/// [destinationAsset] on the person's own Spark wallet. Receive rows and
/// the receive flows (bitcoin and dollars) ask this; sends and venue
/// deposits and withdrawals never do.
List<String> orchestraReceiveAddressCapabilities({
  required String sourceChain,
  required String sourceAsset,
  required String destinationAsset,
}) =>
    [
      'crypto.deposit',
      ...orchestraCapabilityRequirements(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationChain: 'spark',
        destinationAsset: destinationAsset,
      ),
    ];

/// The operator switch for receiving from another network through a
/// ONE-TIME quoted deposit address: the quoted receive screen, reached
/// from the one-time rows of the bitcoin and dollar receive pickers
/// (`kOrchestraQuoteReceiveChains`, and bitcoin into dollars) and from the
/// "one-time address" button beside a reusable address.
///
/// The quote that mints a one-time address is `POST /api/v1/orchestra/quote`
/// from another network (not Spark, Lightning or a venue rail, and not
/// native bitcoin into bitcoin) into the person's own Spark bitcoin or
/// dollars. The backend operation guard refuses exactly that shape while
/// the switch is off; estimates, Move conversions on Spark, sends and
/// venue deposits and withdrawals never consult it, and neither do
/// reusable deposit addresses (accumulation and standing). The app hides
/// the options before the tap and the quoted receive screen re-checks
/// before quoting. Fails closed: with no readable policy it denies, and
/// every one-time receive option disappears while the reusable ones stay.
const kOneTimeAddressCapability = 'orchestra.onetime_addresses';

/// Whether a one-time quoted receive may be offered or started.
bool oneTimeReceiveAllowed(RuntimeCapabilitiesService policy) =>
    policy.allows(kOneTimeAddressCapability);

/// The gates a picker row needs: the move of [option]'s coin on its chain
/// against [otherLegAsset] on the person's own rail, classified exactly as
/// the backend classifies the quote that follows. On a receive picker
/// ([depositAddress]) a row served by a reusable deposit address also
/// needs `crypto.deposit`, as the backend asks of every deposit address
/// it mints; a one-time row is a quote and answers to the quote gates
/// plus [kOneTimeAddressCapability], the app-side switch for one-time
/// receive addresses.
List<String> orchestraOptionCapabilities(OrchestraReceiveOption option,
        {String otherLegAsset = 'BTC', bool depositAddress = false}) =>
    depositAddress && option.reusableAddress
        ? orchestraReceiveAddressCapabilities(
            sourceChain: option.chain,
            sourceAsset: option.assetCode,
            destinationAsset: otherLegAsset,
          )
        : [
            if (depositAddress) kOneTimeAddressCapability,
            ...orchestraCapabilityRequirements(
              sourceChain: option.chain,
              sourceAsset: option.assetCode,
              destinationChain: 'spark',
              destinationAsset: otherLegAsset,
            ),
          ];

/// The rows the policy lets a picker offer, and why the rest are absent.
/// A row is hidden when any of its gates denies; the reason is the first
/// denial's, so the sheet can say it once. Fails closed: with no readable
/// policy the swap gates deny and every cross-chain row disappears, while
/// rows with a venue leg follow their venue rule as before.
({List<OrchestraReceiveOption> offered, String? hiddenReason})
    orchestraOptionsOfferedUnderPolicy(
  List<OrchestraReceiveOption> options,
  RuntimeCapabilitiesService policy, {
  String otherLegAsset = 'BTC',
  bool depositAddress = false,
}) {
  final offered = <OrchestraReceiveOption>[];
  String? reason;
  for (final option in options) {
    String? denied;
    for (final gate in orchestraOptionCapabilities(option,
        otherLegAsset: otherLegAsset, depositAddress: depositAddress)) {
      denied = policy.blockReason(gate);
      if (denied != null) break;
    }
    if (denied == null) {
      offered.add(option);
    } else {
      reason ??= denied;
    }
  }
  return (offered: offered, hiddenReason: reason);
}
