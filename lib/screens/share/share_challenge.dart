// lib/screens/share/share_challenge.dart
//
// CHALLENGE THEM (founder, 4 November 2026: "Entice users on sharing
// predictions to pick the other side on the share. 'I think Bitcoin will
// win, wanna fight me?'"). The app-side pieces of a prediction sent as a
// dare; the link and its flag are in models/share_link_model.dart, the
// card in cards/ (share_card_versus.dart, share_card_copy.dart).
//
//   * THE SENDER: [ShareChallengeToggle], the switch under the name on
//     Send this prediction's "Who is it for?" step (send_to_anyone_sheet
//     .dart), off by default, offered on a prediction pick only (an
//     Investing pick and a plain send have none). On, the live card turns
//     into the dare and the link is created with `challenge: true`, its
//     URL with `?challenge=1`.
//   * THE RECIPIENT: the Claim screen (claim_screen.dart) reads the flag
//     from the URL or the backend, shows the dare as its hero and, once
//     the money is in, offers TWO EXPLICIT CHOICES: "Take the other side"
//     (the bar) and "Same side as your friend" (a text button above it).
//     Nothing is preselected until one is tapped: each opens the slip on
//     its side ([challengeOtherSideIndex] for the other one), and nothing
//     is placed without the person's own tap in the slip.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketOutcome;
import 'package:kute/theme/app_theme.dart';

/// Whether a pick on [venue] can be sent as a dare: predictions only.
bool shareChallengeOffered({required bool hasPick, String? venue}) =>
    hasPick && venue != 'hyperliquid';

/// The side opposite [pick] among a market's [outcomes]: the other of
/// two (No for Yes, the other team). Null when there is no single other
/// side (three or more outcomes, an index out of range): the Claim screen
/// then opens the market with nothing preselected.
int? challengeOtherSideIndex(List<PolymarketOutcome> outcomes, int pick) {
  if (outcomes.length != 2 || pick < 0 || pick > 1) return null;
  return 1 - pick;
}

/// The switch row (see the file header), in the Settings switch's look.
class ShareChallengeToggle extends StatelessWidget {
  const ShareChallengeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return MergeSemantics(
      child: InkWell(
        key: const ValueKey('share-challenge-toggle'),
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.challengeToggle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.challengeToggleSub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              // The Settings switch's look.
              Switch(
                key: const ValueKey('share-challenge-switch'),
                value: value,
                onChanged: onChanged,
                activeThumbColor: context.ctaOnColor,
                activeTrackColor: context.ctaFill,
                inactiveThumbColor: c.textSecondary,
                inactiveTrackColor:
                    context.isDark ? c.surfaceElevated : c.surfaceLight,
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.transparent
                      : c.borderSubtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
