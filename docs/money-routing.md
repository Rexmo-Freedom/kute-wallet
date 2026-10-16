# How Kute moves money

For an order in a venue, fund that venue directly whenever a supported,
approved route exists. Dollars is a source, not a compulsory intermediate stop.

This is a readable contract for the routing code and future regression tests.
The source files linked below execute the policy. This document does not change
routes, provider availability, fees, or approvals. It describes the 2.1.2 hotfix
work on 16 October 2026; device acceptance is still required.

## The balances mean different things

| Name in this document | What actually holds the money |
| --- | --- |
| Bitcoin | Spending wallet's Spark BTC. Savings/on-chain and Ledger paths have separate signing rules. |
| Dollars | USDB token on Spark, `spark:USDB`. This is one component of the combined Investments balance. |
| Predictions | Polymarket cash. Incoming `polygon:USDC.e` must become spendable pUSD before a bet. |
| Investing | Hyperliquid USDC on HyperCore. A HIP-3 market such as `xyz:TSLA` has a separate DEX clearinghouse. |

An Investments total is a presentation of several balances. It does not mean
the money is already in the account that can place a particular order.

## What happens when someone confirms a bet or order

Use sources in this order: cash already in that venue, then Dollars, then
Bitcoin, then the other venue only for the remaining shortfall. The last source
is deliberately last because pulling money between venues adds settlement work.
A remainder below a route minimum can fold into the Bitcoin leg within its
approved cap. “Available” still shows the total.

Source selection is implemented by `planOrderSources` and `decideOrderSources`
in [bitcoin_funded_order.dart](../lib/services/one_balance/bitcoin_funded_order.dart).
When existing funds cover a plan, the order slip and bet slip fund it in place.
If every spendable source is known to be zero, the slip instead opens its
contextual deposit entry so the person can add funds. Unknown or loading
balances do not qualify as zero. A short wallet can still open Receive to
obtain money. The known-zero exception is separate from sending existing funds
through an unnecessary deposit detour.
The deposit leaves the slip open and refreshes it on completion; placing the
order still needs an explicit approval. It does not queue an order or preserve
an old approval. Add margin keeps its existing behavior. See
[empty_slip_sources.dart](../lib/services/one_balance/empty_slip_sources.dart)
and [slip_shortfall.dart](../lib/screens/shared/slip_shortfall.dart).

```mermaid
flowchart LR
    V["Cash already at venue"] --> R["Venue readiness"]
    D["Dollars → target venue"] --> R
    B["Bitcoin → target venue"] --> R
    O["Other venue → target venue<br/>only the remainder"] --> R
    R --> P["Place the approved order"]
```

Selected external source legs start together after approval. Readiness can
start on the first arrival and the order waits until the target venue can
actually cover it. “Priority” chooses how much each source contributes; it
does not require finishing the Dollars leg before starting the Bitcoin leg.
See [money_steps.dart](../lib/services/one_balance/money_steps.dart),
[bitcoin_funded_order.dart](../lib/services/one_balance/bitcoin_funded_order.dart),
and [venue_cash_funded_order.dart](../lib/services/one_balance/venue_cash_funded_order.dart).

## Deposit and movement directions

These are directed routes: support for A → B does not imply B → A. Every route
still requires the live catalog, runtime policy, minimum, verified quote and
the correct wallet ownership. “Direct” means no intermediate Dollars balance;
it can still involve a provider, source settlement and destination credit.

| From → to | Route and necessary follow-up | Code |
| --- | --- | --- |
| Bitcoin → Dollars | `spark:BTC → spark:USDB`, one Orchestra swap. | [Bitcoin leg](../lib/services/one_balance/bitcoin_to_dollars_leg.dart), [Move sheet](../lib/screens/home/components/deposit_sheet.dart) `_dispatchBtcToUsd` |
| Dollars → Bitcoin | `spark:USDB → spark:BTC`, one Orchestra swap. A Buy can pull an approved remainder from venue cash. | [Purchase](../lib/services/one_balance/dollars_to_bitcoin_purchase.dart), [purchase steps](../lib/services/one_balance/buy_bitcoin_steps.dart) |
| Bitcoin → Predictions | `spark:BTC → polygon:USDC.e` to the wallet's own Predictions deposit account, then convert to pUSD and confirm spendability. | [Direct Bitcoin leg](../lib/services/one_balance/bitcoin_to_venue_leg.dart) |
| Bitcoin → Investing | `spark:BTC → hypercore:USDC` to the own Investing account; HIP-3 then needs collateral at its DEX. | [Direct Bitcoin leg](../lib/services/one_balance/bitcoin_to_venue_leg.dart), [Spark/HyperCore service](../lib/services/funding/spark_hypercore_funding_service.dart) |
| Dollars → Predictions | `spark:USDB → polygon:USDC.e`, then pUSD readiness. | [Predictions funder](../lib/services/one_balance/predictions_venue_funder.dart) |
| Dollars → Investing | `spark:USDB → hypercore:USDC`; HIP-3 collateral readiness follows. | [Investing rail](../lib/services/one_balance/hyperliquid_move_rail.dart) |
| Predictions → Dollars | Convert pUSD to the withdrawable USDC.e when required, then `polygon:USDC.e → spark:USDB`. | [Predictions funder](../lib/services/one_balance/predictions_venue_funder.dart) `sweepToDollars` |
| Predictions → Bitcoin | `polygon:USDC.e → spark:BTC` after the necessary pUSD withdrawal conversion. | [Predictions funder](../lib/services/one_balance/predictions_venue_funder.dart) `sweepTo` |
| Predictions → Investing | `polygon:USDC.e → hypercore:USDC` directly to the same wallet's Investing account, after withdrawal conversion if needed. Ownership permits `pmHot → hlHot` in this direction. | [Predictions funder](../lib/services/one_balance/predictions_venue_funder.dart), [owned account guard](../lib/services/funding/owned_address_resolver.dart) |
| Investing → Dollars | Try native `hypercore:USDC → spark:USDB`. When refused before sending, the implemented alternative is HyperCore CCTP to the own Arbitrum standing instruction, then `arbitrum:USDC → spark:USDB`. | [Investing rail](../lib/services/one_balance/hyperliquid_move_rail.dart), [CCTP](../lib/services/hyperliquid/cctp_withdrawal.dart) |
| Investing → Bitcoin | Native `hypercore:USDC → spark:BTC` where supported; implemented CCTP alternative delivers to the own Bitcoin standing instruction. | [Move sheet](../lib/screens/home/components/deposit_sheet.dart) `_dispatchHyperliquidToBtc`, [CCTP](../lib/services/hyperliquid/cctp_withdrawal.dart) |
| Investing → Predictions | CCTP to the own Predictions standing instruction, then pUSD readiness. It avoids an intermediate Dollars balance. | [Cash sources](../lib/services/one_balance/venue_cash_source.dart), [CCTP](../lib/services/hyperliquid/cctp_withdrawal.dart) |

The HyperCore-source native routes were recorded as unavailable in this
candidate's implementation context, so their CCTP alternative matters. Catalog
and quote checks establish availability for the actual attempt; this document
is not a live provider status feed.

An explicitly chosen Bitcoin → Investments deposit can target the combined
balance's Dollars component. That is a different user action from confirming
a Hyperliquid order, whose Bitcoin leg targets HyperCore directly. The spending
wallet's normal Move sheet hides venue deposit/withdraw doors; Ledger keeps
separate device flows. See `spendingWalletLockedSide` and `ledgerMoveRoute` in
[deposit_sheet.dart](../lib/screens/home/components/deposit_sheet.dart).

## Money arriving from outside Kute

| Entry | How the destination is chosen |
| --- | --- |
| Spark BTC / Lightning / on-chain Bitcoin receive | Uses that wallet's native receive path; no cross-chain swap is necessary for a native Bitcoin receipt. |
| Other crypto → Bitcoin or Dollars | A supported directed Orchestra route converts the deposited asset to `spark:BTC` or `spark:USDB`. A reusable address additionally requires standing/accumulation-address support for that exact source and destination. |
| Cash App purchase | A Lightning-funded Orchestra order delivers to the selected supported destination. The external payment must actually arrive before conversion/delivery can complete. |
| Bank transfer | Coming-soon state in the Move sheet; it does not dispatch a payment. |

See [orchestra_routes.dart](../lib/services/orchestra_routes.dart),
[receive route availability](../lib/services/orchestra/receive_route_availability.dart),
[standing deposit store](../lib/services/orchestra/standing_deposit_store.dart),
and [Move sheet](../lib/screens/home/components/deposit_sheet.dart).
An advertised swap pair alone does not prove a reusable address can be minted.

## When a direct leg may use Dollars instead

The decision happens before that leg sends. A fallback is not permission to
retry a payment that might already have left.

| Fixed reason | Meaning |
| --- | --- |
| `no_own_deposit` | The wallet's own destination could not be established. |
| `refused_recently` | This direct route has a recent route-level refusal. |
| `estimate_unavailable` | Required pricing/readiness information did not arrive or was invalid. |
| `costlier` | The direct plan exceeds the compared via-Dollars cost. |
| `over_cap` | Required sats exceed the wallet or approved direct-leg limit. |
| `below_minimum` | The direct leg cannot meet the route minimum within the valid plan. |

The Bitcoin decision and `route_reason` values live in
[bitcoin_to_venue_leg.dart](../lib/services/one_balance/bitcoin_to_venue_leg.dart).
The direct Bitcoin → Hyperliquid plan must not wait on an irrelevant
Dollars-only route when it uses no Dollars. Its own route still needs a valid
estimate, minimum, destination, cost comparison and approval cap.

Venue cash has separate refusal codes. A temporary network/terms read can be
retried once while the same approval still covers it; a wallet ownership guard
refusal is not retried. A direct refusal before submission may replace the leg
with source → Dollars → destination steps. An ambiguous or already submitted
transfer is followed by status reconciliation instead. See
[venue_cash_source.dart](../lib/services/one_balance/venue_cash_source.dart) and
[settlement_http.dart](../lib/services/funding/settlement_http.dart).

Quotes pin the directed pair, amounts and own recipient. One user approval
limits each leg and the total. A changed or expired approval cannot silently
authorize more money. Automatic sweeping is disabled
(`kVenueAutoSweepEnabled = false` in
[venue_sweeper.dart](../lib/services/one_balance/venue_sweeper.dart)); money does
not move merely because the combined balance is displayed.

## Why a purchase can feel slow

An exchange order is the last stage, not the whole operation. The critical path
can be: fresh policy/location checks → estimates/quote → approval → source
send → provider registration → cross-chain delivery → venue credit/conversion
→ order submission → confirmed result. A via-Dollars route repeats the
quote/send/delivery sequence for its onward leg. A Predictions withdrawal can
also require a relayed pUSD conversion, and CCTP has its own transfer and
standing-order discovery stages. Independent source legs run in parallel;
dependent conversions and spends must wait for real funds.

There are two different delays: the funds arriving and the app noticing usable
funds. Orchestra delivery status, the SDK's token cache and the venue's
spendable-balance view are different signals. Updating a hero number does not
prove an order can spend it; a stale hero must not make an arrived deposit look
lost. The settlement graph distinguishes those steps.

### Current wait settings, not measured delivery times

| Wait | Code setting and meaning | Source |
| --- | --- | --- |
| Gated policy tap / manual connection check | 4 s / 5 s foreground bounds. They do not predict swap duration. | [Runtime capabilities](../lib/services/runtime_capabilities_service.dart), [region freshness](../lib/services/region_freshness.dart) |
| Direct Bitcoin route estimate / limits | Each has a 4 s request ceiling. Independent reads run together. | [Direct Bitcoin leg](../lib/services/one_balance/bitcoin_to_venue_leg.dart) |
| Direct funded leg delivery | Status every 1 s, slow indication after 2 min, foreground wait at most 12 min. | [Direct Bitcoin leg](../lib/services/one_balance/bitcoin_to_venue_leg.dart) `watchOrchestraLeg` |
| Bitcoin → Dollars arrival watcher | Cached check every 1 s; fresh reads every 300 ms for the first 60 s; slow after 2 min; at most 12 min. | [Bitcoin/Dollars leg](../lib/services/one_balance/bitcoin_to_dollars_leg.dart) |
| Venue-cash runner | Leg wait at most 12 min; after authoritative home-leg delivery, Dollars catch-up at most 30 s with 500 ms checks. | [Venue-cash runner](../lib/services/one_balance/venue_cash_funded_order.dart) |
| Hyperliquid account credit | Poll every 1 s for 30 s, then every 4 s; at most 12 min awaiting funds. | [Pending order](../lib/providers/pending_hyperliquid_order_provider.dart) |
| HIP-3 collateral transfer credit | Read every 300 ms, bounded at 8 s; retry reads without resending the transfer. | [DEX cash](../lib/services/hyperliquid/hypercore_dex_cash.dart) |
| CCTP immediate watcher | Confirm every 1 s / watch every 4 s, for at most 20 min; persisted reconciliation continues separately. | [CCTP](../lib/services/hyperliquid/cctp_withdrawal.dart) |

These timers belong to different phases and are not a single end-to-end SLA.
A foreground timeout can leave money still settling. Persisted Activity and
reconciliation must continue to show where it is; timing out never means it is
safe to send the same funds again.

## Fees: direct routing is not a second fee promise

Read-only public backend policy checked on 16 October 2026 at 12:35:30 UTC
(revision 2). These are Kute's published conversion rates before any verified
referral discount; a validated quote remains authoritative for a specific move.
Provider spread, network costs and exchange fees are separate.

| Direction / operation | Published Kute rate |
| --- | --- |
| Bitcoin → Dollars, Predictions or Investing | 0 bps (0%) |
| Dollars → Bitcoin or venue | `usdb_swap_send`: 50 bps (0.50%) |
| Predictions → Dollars | `usdb_swap_deposit`: 0 bps |
| Predictions → own Investing | `venue_deposit`: 0 bps |
| Predictions → Bitcoin | `predictions_send`: 50 bps (0.50%) |
| Investing → Bitcoin, generic withdrawal rule | `venue_withdrawal`: 50 bps (0.50%) |
| Other cross-chain crypto deposit / send | 50 bps (0.50%) |
| Standard fiat deposit | 100 bps (1%); the native Bitcoin fiat route has a specific waiver. |
| Hyperliquid builder fee on orders | Default/listed 10 tenths of a basis point = 1 bp = 0.01% of order notional; exchange fees are extra. |
| Polymarket builder fee on orders | Current CLOB builder rate: taker 20 bps (0.20%), maker 0; market/platform fees may also apply. |

Classification order matters: a Dollars destination is checked first, then a
Dollars source, then an Investing destination/source, then a Polygon
destination/source. Thus Dollars → Investing uses the Dollars-send rate even
though Bitcoin → Investing has a zero Kute conversion rate.

The published referral reduction is 20 basis points on a positive Kute
conversion fee: for an eligible verified referred session, 50 → 30 bps and
100 → 80 bps. It does not add a charge to a waived fee and does not establish a
discount on venue builder fees. A published `trading`
rule of `provider_default` with `bps: 0` does not mean venue trading is free.

The Hyperliquid rate is the configured production builder rate. Debug builds
can omit Kute's builder if its approval fails; release builds require the
configured approval and refuse that unapproved order. Do not infer production
builder revenue from the founder's debug trades. See `_builderFee` in
[hyperliquid_trading_provider.dart](../lib/providers/hyperliquid_trading_provider.dart).
Use the quote/provider's net amounts; do not subtract a fee a second time.

CCTP uses verified standing-instruction fee terms. An own-account instruction
can pin `investments_internal` at 0; a legacy `venue_withdrawal` instruction can
carry 50 bps. The public global policy does not establish a particular wallet's
internal instruction, so do not promise every Investing withdrawal is free.

App enforcement and quote amounts:
[standing_deposit_store.dart](../lib/services/orchestra/standing_deposit_store.dart),
[cctp_withdrawal.dart](../lib/services/hyperliquid/cctp_withdrawal.dart), and
[orchestra_fee_amount.dart](../lib/services/orchestra/orchestra_fee_amount.dart).
The backend classifier is `internal/proxy/orchestra_runtime.go` in the backend
repository. This snapshot does not modify its policy.

## What improves speed

Validated changes in this batch:

- Fresh policy and venue checks start after the tap on dedicated connections;
  manual/network changes recycle the shared connection pools. This avoids an
  old connection or request holding the old VPN result. Targeted tests: 89.
- Search and old saved HIP-3 descriptors retain the target DEX. The readiness
  line waits for that DEX's collateral credit; it never resends a transfer
  merely because indexing is slow. Bitcoin-only Investing plans skip irrelevant
  Dollars-only reads, and a short via-Dollars output stops explicitly.
  Targeted tests: 108.
- USDB catch-up keeps retrying a numeric reading that fails to reflect a new
  settled arrival, including an unchanged zero. After normal sync recovery, one
  guarded SDK reconnect can refresh its token store and re-subscribe existing
  listeners. It is excluded during native mutations, shared sync, pending
  outgoing payments and observed token optimization. Targeted tests: 96 unique.
  The SDK source supports leaf-refresh failure and token Swap reservations as
  possible causes; the device's exact native cause remains unproven.
- The Investing and Predictions slips open the contextual deposit only after
  the sources are proven empty, including fresh synced SDK reads, known venue
  balances, no positive ledger conflict and no pending/waiting money. Loading
  or conflicting reads retain the ordinary flow. Targeted tests: 38.

These are code/test results, not measured end-to-end latency or device proof.
The following are proposed follow-ups, not additional changes in this hotfix:

| Improve actual completion | Improve the experience while it completes |
| --- | --- |
| Audit remaining unnecessary serial reads on each route, using the direct Bitcoin fix as the regression contract. | Check every entry path renders all source lines immediately and completes each independently, using the existing step widgets. |
| Measure repeated read/estimate calls before removing or caching any; reuse only policy allows explicitly permitted by execution gates. | Check “sent”, “delivered”, “crediting”, “converting” and “placing” stay accurate on slow and failed paths. |
| Extend authoritative delivery/credit notifications to paths still relying on their next polling tick, retaining polling for recovery. | Audit fallback copy and stopped runs so each names the remaining work and where funds are held. |
| Measure phase durations by route before tuning intervals or provider integrations; never infer settlement time from a timeout constant. | Verify no path claims success before venue confirmation or presents an unknown balance as $0.00. |

Existing graph and rendering: [money_steps.dart](../lib/services/one_balance/money_steps.dart),
[venue_readiness.dart](../lib/services/one_balance/venue_readiness.dart), and
[move_steps.dart](../lib/services/one_balance/move_steps.dart).
No new chrome is required. Measurements must use exact values and exclude keys,
addresses, payment/order identifiers and whole-wallet balances from analytics.
