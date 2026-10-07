// lib/screens/ledger/funding/ledger_deposit_source_sheet.dart
//
// Where a Ledger's venue deposit takes its money from.
//
// This used to be three stacked buttons in a Ledger frame, which looked
// nothing like the same choice on the spending account. That one is a
// list: a mark, the source's name, a line of detail under it, and a
// chevron. It reads the same way here now (user decision September
// 2026: a Ledger surface matches its Home counterpart). A source that
// does not exist here is left out, and so is an onramp Kute's policy
// does not offer (founder decision, October 2026: see [onrampVisible]).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// `bank` is retained because callers still switch on it; this sheet
/// never returns it: the bank rail is hidden unless the runtime policy
/// offers `onramp.bank`, and the Move sheet refuses to switch to it
/// while hidden. `cashApp` is returned only while the policy offers
/// `onramp.cashapp`; callers do not open this sheet when Bitcoin would
/// be its only row.
enum LedgerDepositSource { bitcoin, cashApp, bank }

Future<LedgerDepositSource?> showLedgerDepositSourceSheet(BuildContext context,
        {required bool predictions}) =>
    showAppBottomSheet<LedgerDepositSource>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final c = context.colors;
          final l10n = context.l10n;
          final cashAppVisible = onrampVisible(
              ref.watch(runtimeCapabilitiesProvider), kOnrampCashApp);
          return AppBottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12.h, bottom: 20.h),
                    child: AppDecorations.dragHandle(context),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.depositToPickerTitle} '
                        '${predictions ? l10n.predictions : l10n.ledgerTabInvesting}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 28.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        l10n.depositPickHowYouWantToPay,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                _SourceRow(
                  asset: 'lib/assets/bitcoin-icon.svg',
                  title: l10n.bitcoin,
                  subtitle: l10n.ledgerTabBitcoin,
                  onTap: () => Navigator.of(sheetContext)
                      .pop(LedgerDepositSource.bitcoin),
                ),
                if (cashAppVisible)
                  _SourceRow(
                    asset: 'lib/assets/cashapp-logo.svg',
                    title: 'Cash App',
                    subtitle: l10n.deposit,
                    onTap: () => Navigator.of(sheetContext)
                        .pop(LedgerDepositSource.cashApp),
                  ),
                SizedBox(height: 8.h),
              ],
            ),
          );
        },
      ),
    );

/// One source, in the same shape the spending account's picker uses: a
/// 36 mark, the name, a quiet line under it, and a chevron.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    this.asset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String? asset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          child: Row(
            children: [
              if (asset != null)
                SvgPicture.asset(asset!, width: 36.sp, height: 36.sp),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2)),
                    SizedBox(height: 3.h),
                    Text(subtitle,
                        style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(Icons.chevron_right_rounded,
                  color: c.textTertiary, size: 22.sp),
            ],
          ),
        ),
      ),
    );
  }
}
