import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';

/// Entry units offered on the Send and Receive amount steps, in the order
/// the sheet lists them.
const List<String> kAmountUnitCodes = [
  'Sats',
  'BTC',
  'USD',
  'EUR',
  'BRL',
  'GBP',
  'CHF',
];

/// One unit picker for Send and Receive: header, one roomy row per unit
/// with the unit's name, a selected check, Cancel. Callers pass the icon
/// they already draw for a code and handle the pick.
Future<void> showAmountUnitPicker(
  BuildContext context, {
  required String selected,
  required ValueChanged<String> onSelected,
  required Widget Function(String code, double size) iconBuilder,
  List<String> codes = kAmountUnitCodes,
}) {
  final l10n = context.l10n;
  String nameFor(String code) => switch (code) {
        'Sats' => l10n.sendUnitSats,
        'BTC' => l10n.sendUnitBtc,
        'USD' => l10n.currencyNameUsd,
        'EUR' => l10n.currencyNameEur,
        'BRL' => l10n.currencyNameBrl,
        'GBP' => l10n.currencyNameGbp,
        'CHF' => l10n.currencyNameChf,
        _ => code,
      };
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendAmountUnitTitle,
            subtitle: l10n.sendAmountUnitSubtitle,
          ),
          SizedBox(height: 8.h),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final code in codes)
                    AppBottomSheetListTile(
                      title: code,
                      subtitle: nameFor(code),
                      leading: iconBuilder(code, 24.sp),
                      isSelected: code == selected,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(sheetContext).pop();
                        onSelected(code);
                      },
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 8.h),
          AppBottomSheetTextButton(
            text: l10n.cancel,
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    ),
  );
}

// ─── Shared unit chrome ───────────────────────────────────────────
//
// The chip under the hero figure, and the per-unit rules the keypad and
// the prefix follow. Extracted so every amount step wears the same unit
// control rather than redrawing its own.
