// lib/screens/polymarket/components/clear_rules_sheet.dart
//
// Bottom sheet shown when the user taps Clear on a LOST resolved
// position. Surfaces the market's FULL resolution rules (fetched live
// from gamma by conditionId) so the user always sees WHY the bet lost,
// with the Clear action itself as the sheet's bottom CTA. Same modal
// grammar as the app's other bottom sheets (user decision: no separate
// "why" button; the rules gate the Clear).
//
// Born from a real support case: a user bet Yes on a soccer moneyline,
// the match drew in regulation, and the LOST card read as a data bug
// because the "first 90 minutes only" rule was never surfaced.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Rules text per conditionId. A resolved market's description never
/// changes, so one fetch per market per session.
final Map<String, String> _rulesCache = {};

/// Resolution rules (Gamma market `description`) for [conditionId], or null
/// when Gamma has none. Reads `/markets/keyset` (the offset-paged `/markets`
/// is being deprecated); the keyset response is `{"markets": [...]}`.
/// [client] is injectable for tests.
Future<String?> fetchPolymarketMarketRules(
  String conditionId, {
  http.Client? client,
}) async {
  final cached = _rulesCache[conditionId];
  if (cached != null) return cached;
  // Gamma's list endpoints hide resolved markets unless closed=true is
  // passed explicitly (verified live: without it the query returns []).
  // Try closed first (the Clear flow only exists for settled markets),
  // then the unfiltered variant as a safety net.
  for (final params in [
    {'condition_ids': conditionId, 'closed': 'true', 'limit': '1'},
    {'condition_ids': conditionId, 'limit': '1'},
  ]) {
    try {
      final uri = Uri.parse('https://gamma-api.polymarket.com/markets/keyset')
          .replace(queryParameters: params);
      final resp = await (client == null ? http.get(uri) : client.get(uri))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      final body =
          decoded is Map<String, dynamic> ? decoded['markets'] : null;
      if (body is! List || body.isEmpty) continue;
      final first = body.first;
      if (first is! Map<String, dynamic>) continue;
      final desc = first['description'] as String?;
      if (desc != null && desc.trim().isNotEmpty) {
        return _rulesCache[conditionId] = desc.trim();
      }
    } catch (_) {/* try the next variant */}
  }
  return null;
}

/// Opens the rules-then-Clear sheet for a lost position. [onClear]
/// performs the actual redeem including its own success and error
/// surfacing. It is supplied by the resolved card so the card's Claim
/// path and this sheet share one redeem implementation.
Future<void> showClearRulesSheet(
  BuildContext context, {
  required PolymarketPosition pos,
  required Future<void> Function() onClear,
}) {
  return showAppBottomSheet(
    context: context,
    builder: (_) => _ClearRulesSheet(pos: pos, onClear: onClear),
  );
}

class _ClearRulesSheet extends StatefulWidget {
  final PolymarketPosition pos;
  final Future<void> Function() onClear;
  const _ClearRulesSheet({required this.pos, required this.onClear});

  @override
  State<_ClearRulesSheet> createState() => _ClearRulesSheetState();
}

class _ClearRulesSheetState extends State<_ClearRulesSheet> {
  late final Future<String?> _rules =
      fetchPolymarketMarketRules(widget.pos.marketId);
  bool _clearing = false;

  Future<void> _handleClear() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      // The card-supplied redeem shows its own snackbars/overlays.
      await widget.onClear();
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
        // Close the sheet whatever the outcome. On success the row is
        // clearing; on error the card's snackbar is now visible.
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Center(child: AppDecorations.dragHandle(context)),
            ),
            SizedBox(height: 18.h),
            Text(
              context.l10n.clearRulesTitle,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 24.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              widget.pos.marketQuestion,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.35,
              ),
            ),
            SizedBox(height: 14.h),
            // The rules body. Scrolls internally; descriptions run about
            // 600 to 2000 chars so the sheet never trims them.
            Flexible(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: FutureBuilder<String?>(
                  future: _rules,
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 28.h),
                        child: Center(
                          child: LoadingAnimationWidget.staggeredDotsWave(
                            color: c.textTertiary,
                            size: 26.sp,
                          ),
                        ),
                      );
                    }
                    final rules = snap.data;
                    return SingleChildScrollView(
                      child: Text(
                        rules ??
                            context.l10n.clearRulesUnavailable,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: 16.h),
            AppButton(
              text: context.l10n.clear,
              isLoading: _clearing,
              onPressed: _clearing ? null : _handleClear,
            ),
          ],
        ),
      ),
    );
  }
}
