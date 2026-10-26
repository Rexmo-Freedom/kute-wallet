import 'dart:math' show max;

/// Flat sat ceiling on the Spark service claim quote, identical to the
/// previous 25 sat/vB x 99 vB. The SDK's own automatic claim runs under it
/// (`maxDepositClaimFee`), and it is the floor of the app's automatic claim.
const int kSparkAutoClaimMaxFeeSats = 2475;

/// Share of the deposit the app pays automatically to claim it, above the
/// [kSparkAutoClaimMaxFeeSats] floor: 0.25 %, so a 0.119 BTC deposit is
/// claimed on its own up to a 29,750 sat fee. The Spark provider prices
/// large deposits with a share of the amount, which the flat floor alone
/// always refused. Founder choice, 2026-10-26 (option B).
const double kSparkAutoClaimMaxFeeShareOfDeposit = 0.0025;

/// The most the app pays on its own to claim a deposit of [depositSats]:
/// the fixed floor or 0.25 % of the deposit, whichever is larger. Above it
/// the deposit waits for a lower fee, with Claim now on its sheet.
int sparkAutoClaimCeilingSats(int depositSats) => max(kSparkAutoClaimMaxFeeSats,
    (depositSats * kSparkAutoClaimMaxFeeShareOfDeposit).floor());

/// Whether the app claims, on its own, a deposit of [depositSats] that the
/// SDK refused for a required fee of [requiredFeeSats]: the fee is within
/// [sparkAutoClaimCeilingSats] and below the deposit itself.
bool sparkAutoClaimCovers(
        {required int requiredFeeSats, required int depositSats}) =>
    requiredFeeSats > 0 &&
    requiredFeeSats < depositSats - 1 &&
    requiredFeeSats <= sparkAutoClaimCeilingSats(depositSats);
