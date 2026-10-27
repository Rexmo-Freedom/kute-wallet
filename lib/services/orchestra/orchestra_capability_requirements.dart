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
///
/// Bitcoin to bitcoin ([orchestraBitcoinOnlyRoute]: bitcoin, Lightning or
/// Spark on both legs, no dollars) is plain bitcoin, which no region ever
/// blocks, and Dollars into Bitcoin ([orchestraDollarsToBitcoinRoute]) is
/// an exit: the backend's guard ignores country rules on `orchestra.swap`
/// for both, so a COUNTRY refusal of the master (`country_*`, read from
/// [policy], the app's own by default) asks nothing of them. Only the
/// master switched off for everyone still stops them.
List<String> orchestraCapabilityRequirements({
  required String sourceChain,
  required String sourceAsset,
  required String destinationChain,
  required String destinationAsset,
  RuntimeCapabilitiesService? policy,
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
  if (orchestraBitcoinOnlyRoute(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationChain: destinationChain,
          destinationAsset: destinationAsset) ||
      orchestraDollarsToBitcoinRoute(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationChain: destinationChain,
          destinationAsset: destinationAsset)) {
    final swap = (policy ?? RuntimeCapabilitiesService.instance)
        .decision('orchestra.swap');
    if (!swap.allowed &&
        !swap.comingSoon &&
        swap.reason.startsWith('country_')) {
      return const [];
    }
  }
  return [
    'orchestra.swap',
    if (orchestraSwapClassCapability(sourceAsset, destinationAsset)
        case final gate?)
      gate,
  ];
}

/// Whether a route moves bitcoin to bitcoin on the person's bitcoin rails
/// (`bitcoin`, `lightning` or `spark` on both legs, BTC on both, never
/// the dollar balance): the shape the backend exempts from country rules
/// on `orchestra.swap`.
bool orchestraBitcoinOnlyRoute({
  required String sourceChain,
  required String sourceAsset,
  required String destinationChain,
  required String destinationAsset,
}) {
  const rails = {'bitcoin', 'lightning', 'spark'};
  return rails.contains(sourceChain.trim().toLowerCase()) &&
      rails.contains(destinationChain.trim().toLowerCase()) &&
      sourceAsset.trim().toUpperCase() == 'BTC' &&
      destinationAsset.trim().toUpperCase() == 'BTC';
}

/// Whether a route converts the dollar balance (`spark:USDB`) into the
/// person's own bitcoin on a bitcoin rail: an exit the backend exempts
/// from country rules on `orchestra.swap`. Bitcoin into Dollars is not.
bool orchestraDollarsToBitcoinRoute({
  required String sourceChain,
  required String sourceAsset,
  required String destinationChain,
  required String destinationAsset,
}) =>
    sourceChain.trim().toLowerCase() == 'spark' &&
    sourceAsset.trim().toUpperCase() == 'USDB' &&
    orchestraBitcoinOnlyRoute(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: destinationChain,
        destinationAsset: destinationAsset);

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
/// backend's operation guard asks them of a standing Receive registration
/// (`PUT /standing-deposit-addresses/{ref}`): `crypto.deposit` first, then the route from [sourceChain]/[sourceAsset] into
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
/// ONE-TIME quoted deposit address: the fallback of every coin row of the
/// Dollars receive and of the Bitcoin receive's "other coins" whose
/// reusable (standing) address cannot serve it (`receiveOtherCoinOptions`).
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
/// every receive-from-another-network option disappears.
const kOneTimeAddressCapability = 'orchestra.onetime_addresses';

/// The destination classes that refine [kOneTimeAddressCapability] on the
/// backend, the way the swap classes refine `orchestra.swap`: a one-time
/// receive quote needs the master AND the class of what it lands in,
/// `spark:BTC` (Bitcoin) or `spark:USDB` (Dollars). Both ship on. With
/// Dollars denied the Dollars receive keeps only its reusable rows while
/// the Bitcoin receive's "other coins" still fall back to one-time into
/// bitcoin; with Bitcoin denied the Bitcoin receive offers only the
/// reusable route into dollars.
///
/// A backend older than the classes publishes neither id, which is never
/// read as a denial: only an explicit refusal counts
/// ([oneTimeDestinationDecision]). Never passed to `ensureAllAllowed`, which
/// refuses an id the policy does not name.
const kOneTimeBitcoinCapability = 'orchestra.onetime_addresses.bitcoin';
const kOneTimeDollarsCapability = 'orchestra.onetime_addresses.dollars';

/// The class capability a one-time receive into spark:[destinationAsset]
/// needs: [kOneTimeBitcoinCapability] for `BTC`, else
/// [kOneTimeDollarsCapability] (`USDB`).
String oneTimeDestinationCapability(String destinationAsset) =>
    destinationAsset.trim().toUpperCase() == 'BTC'
        ? kOneTimeBitcoinCapability
        : kOneTimeDollarsCapability;

/// [policy]'s decision for one-time receives into spark:[destinationAsset],
/// read leniently: an id the policy does not carry (`unknown_capability`,
/// or `policy_unavailable` when only an older public policy answered) is
/// allowed, so an older backend keeps working; the master
/// [kOneTimeAddressCapability] still fails closed on its own. Only an
/// explicit denial (switched off, a region, version or platform rule, or
/// coming soon) refuses.
CapabilityDecision oneTimeDestinationDecision(
    RuntimeCapabilitiesService policy, String destinationAsset) {
  final decision =
      policy.decision(oneTimeDestinationCapability(destinationAsset));
  if (decision.allowed && !decision.comingSoon) return decision;
  if (!decision.comingSoon &&
      (decision.reason == 'unknown_capability' ||
          decision.reason == 'policy_unavailable')) {
    return CapabilityDecision(allowed: true, reason: decision.reason);
  }
  return decision;
}

/// Null when one-time receives into spark:[destinationAsset] are allowed
/// (or the class is absent); otherwise the sentence the denial gives.
String? oneTimeDestinationBlockReason(
    RuntimeCapabilitiesService policy, String destinationAsset) {
  final decision = oneTimeDestinationDecision(policy, destinationAsset);
  return decision.allowed && !decision.comingSoon ? null : decision.message;
}

/// Throws [CapabilityUnavailableException] when the class of
/// spark:[destinationAsset] is explicitly denied. Read right after
/// `ensureAllAllowed` refreshed the policy for the strict gates.
void ensureOneTimeDestinationAllowed(
    RuntimeCapabilitiesService policy, String destinationAsset) {
  final decision = oneTimeDestinationDecision(policy, destinationAsset);
  if (!decision.allowed || decision.comingSoon) {
    throw CapabilityUnavailableException(
        oneTimeDestinationCapability(destinationAsset), decision);
  }
}

/// Whether a one-time quoted receive may be offered or started: the master
/// switch, and, given [destinationAsset], its destination class.
bool oneTimeReceiveAllowed(RuntimeCapabilitiesService policy,
        {String? destinationAsset}) =>
    policy.allows(kOneTimeAddressCapability) &&
    (destinationAsset == null ||
        oneTimeDestinationBlockReason(policy, destinationAsset) == null);

/// The operator switch for REUSABLE (standing) Receive addresses: the
/// primary way another coin reaches the dollar balance (`spark:USDB`), from
/// the Dollars receive and from the Bitcoin receive's "other coins". Off,
/// the backend refuses every standing Receive registration as an
/// unavailable route (422 `unsupported_route`); addresses already handed
/// out keep receiving. A backend older than the switch publishes no such
/// id, which is never read as a denial here: see
/// `standingAddressPolicy` (reusable_deposit_address.dart). Never passed to
/// `ensureAllAllowed`, which refuses an id the policy does not name.
const kStandingAddressCapability = 'orchestra.standing_addresses';

/// The gates a picker row needs: the move of [option]'s coin on its chain
/// against [otherLegAsset] on the person's own rail, classified exactly as
/// the backend classifies the quote that follows. On a receive picker
/// ([depositAddress]) a row served by a reusable deposit address also
/// needs `crypto.deposit`, as the backend asks of every deposit address
/// it mints; a one-time row is a quote and answers to
/// [kOneTimeAddressCapability] (the switch for one-time receive
/// addresses), `crypto.deposit` (every new deposit address) and the quote
/// gates. Its destination class ([oneTimeDestinationCapability]) is read
/// leniently beside these and so is not in this list:
/// [orchestraOptionsOfferedUnderPolicy] and the quoted receive screen ask
/// it ([oneTimeDestinationBlockReason], [ensureOneTimeDestinationAllowed]).
///
/// [reusableLegAsset] is what a reusable row delivers when it is not
/// [otherLegAsset]: the Bitcoin receive's "other coins" lists reusable
/// rows that pay the dollar balance (`USDB`) beside one-time rows that pay
/// bitcoin.
List<String> orchestraOptionCapabilities(OrchestraReceiveOption option,
        {String otherLegAsset = 'BTC',
        bool depositAddress = false,
        String? reusableLegAsset}) =>
    depositAddress && option.reusableAddress
        ? orchestraReceiveAddressCapabilities(
            sourceChain: option.chain,
            sourceAsset: option.assetCode,
            destinationAsset: reusableLegAsset ?? otherLegAsset,
          )
        : [
            if (depositAddress) ...[
              kOneTimeAddressCapability,
              'crypto.deposit'
            ],
            ...orchestraCapabilityRequirements(
              sourceChain: option.chain,
              sourceAsset: option.assetCode,
              destinationChain: 'spark',
              destinationAsset: otherLegAsset,
            ),
          ];

/// The rows the policy lets a picker offer, and why the rest are absent.
/// A row is hidden when any of its gates denies, a one-time receive row
/// also when its destination class ([otherLegAsset]) is explicitly denied;
/// the reason is the first denial's, so the sheet can say it once. Fails
/// closed: with no readable policy the swap gates deny and every
/// cross-chain row disappears, while rows with a venue leg follow their
/// venue rule as before.
///
/// A REGION block hides nothing (founder decision, 27 October 2026): a
/// row whose only refusals are region blocks ([keepRegionBlocked], the
/// pickers) stays listed exactly as today, and its tap says why instead
/// of opening its flow ([orchestraOptionRegionBlock]). A caller that
/// must only ever get a row it can use passes false.
({List<OrchestraReceiveOption> offered, String? hiddenReason})
    orchestraOptionsOfferedUnderPolicy(
  List<OrchestraReceiveOption> options,
  RuntimeCapabilitiesService policy, {
  String otherLegAsset = 'BTC',
  bool depositAddress = false,
  String? reusableLegAsset,
  bool keepRegionBlocked = true,
}) {
  final offered = <OrchestraReceiveOption>[];
  String? reason;
  bool open(CapabilityDecision d) => d.allowed && !d.comingSoon;
  for (final option in options) {
    CapabilityDecision? denied;
    final decisions = [
      for (final gate in orchestraOptionCapabilities(option,
          otherLegAsset: otherLegAsset,
          depositAddress: depositAddress,
          reusableLegAsset: reusableLegAsset))
        () => policy.decision(gate),
      if (depositAddress && !option.reusableAddress)
        () => oneTimeDestinationDecision(policy, otherLegAsset),
    ];
    for (final decide in decisions) {
      final decision = decide();
      if (open(decision)) continue;
      if (keepRegionBlocked && decision.regionRestricted) continue;
      denied = decision;
      break;
    }
    if (denied == null) {
      offered.add(option);
    } else {
      reason ??= denied.message;
    }
  }
  return (offered: offered, hiddenReason: reason);
}

/// Kute's region refusal of [capability], as a picker row's tap shows it.
typedef CapabilityRegionBlock = ({
  String capability,
  CapabilityDecision decision
});

/// The first of [capabilities] [policy] refuses for a region (its own
/// block or one it inherits through the backend's `requires` cascade), or
/// null. Any other refusal is not a region block and gives null.
CapabilityRegionBlock? capabilityRegionBlock(
    RuntimeCapabilitiesService policy, Iterable<String> capabilities) {
  for (final id in capabilities) {
    final decision = policy.decision(id);
    if (!decision.allowed &&
        !decision.comingSoon &&
        decision.regionRestricted) {
      return (capability: id, decision: decision);
    }
  }
  return null;
}

/// The region block standing in front of a picker row, or null when the
/// row is open: the first of its gates ([orchestraOptionCapabilities],
/// the standing switch for a reusable receive row, the destination class
/// for a one-time one) that [policy] refuses for a region, its own block
/// or one inherited through the backend's `requires` cascade. The row
/// stays listed; its tap shows this instead of opening its flow.
CapabilityRegionBlock? orchestraOptionRegionBlock(
  OrchestraReceiveOption option,
  RuntimeCapabilitiesService policy, {
  String otherLegAsset = 'BTC',
  bool depositAddress = false,
  String? reusableLegAsset,
}) =>
    capabilityRegionBlock(policy, [
      ...orchestraOptionCapabilities(option,
          otherLegAsset: otherLegAsset,
          depositAddress: depositAddress,
          reusableLegAsset: reusableLegAsset),
      if (depositAddress && option.reusableAddress) kStandingAddressCapability,
      if (depositAddress && !option.reusableAddress)
        oneTimeDestinationCapability(otherLegAsset),
    ]);

/// Whether [policy] refuses [capability] for a region (and for nothing
/// else): what a listing keeps on show behind a tap that says why.
bool capabilityRegionBlocked(
    RuntimeCapabilitiesService policy, String capability) {
  final decision = policy.decision(capability);
  return !decision.allowed && !decision.comingSoon && decision.regionRestricted;
}
