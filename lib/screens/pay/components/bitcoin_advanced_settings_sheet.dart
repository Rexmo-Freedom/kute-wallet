import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_text_field.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Network speed sheet for bitcoin sends: Fast / Standard / Slow rows in
/// the app's picker vocabulary, with the custom sat/vB rate behind an
/// Advanced disclosure so the simple choice stays simple. Hot-wallet
/// Review and the hardware Sign page open the same sheet; both write
/// `sendBlocksProvider` and `customFeeRateProvider`, so whichever one
/// finishes the flow picks up the user's last choice.
void showBitcoinAdvancedSettings(BuildContext context, WidgetRef ref) {
  showAppBottomSheet(
    context: context,
    builder: (sheetContext) => const _NetworkSpeedSheet(),
  );
}

class _NetworkSpeedSheet extends ConsumerStatefulWidget {
  const _NetworkSpeedSheet();

  @override
  ConsumerState<_NetworkSpeedSheet> createState() => _NetworkSpeedSheetState();
}

class _NetworkSpeedSheetState extends ConsumerState<_NetworkSpeedSheet> {
  late final TextEditingController _customController;
  late final FocusNode _customFocus;
  late final ScrollController _scrollController;
  late bool _advancedOpen;
  double? _parsedCustom;

  @override
  void initState() {
    super.initState();
    final customRate = ref.read(customFeeRateProvider);
    _customController = TextEditingController(
        text: customRate == null ? '' : _formatRate(customRate));
    _parsedCustom = customRate;
    // A custom rate already in force is the one thing the user came back
    // for, so the disclosure opens on it.
    _advancedOpen = customRate != null;
    _customFocus = FocusNode();
    _scrollController = ScrollController();
    _customFocus.addListener(_onCustomFocus);
  }

  void _onCustomFocus() {
    if (!_customFocus.hasFocus) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final bottom = _scrollController.position.maxScrollExtent;
      if (reduceMotion) {
        _scrollController.jumpTo(bottom);
        return;
      }
      _scrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _customFocus.removeListener(_onCustomFocus);
    _customFocus.dispose();
    _customController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static String _formatRate(double rate) =>
      rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1);

  void _pickSpeed(_SpeedOption option) {
    ref.read(customFeeRateProvider.notifier).state = null;
    ref.read(sendBlocksProvider.notifier).state = option.blocks;
    TrackingService.track('pay_fee_tier_selected', params: {
      'fee_tier': option.tier,
      'payment_type': 'bitcoin',
    });
    Navigator.of(context).pop();
  }

  void _applyCustom() {
    final rate = _parsedCustom;
    if (rate == null) return;
    ref.read(customFeeRateProvider.notifier).state = rate;
    TrackingService.track('pay_fee_tier_selected', params: {
      'fee_tier': 'custom',
      'payment_type': 'bitcoin',
    });
    Navigator.of(context).pop();
  }

  void _onCustomChanged(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    final parsed = value != null && value.isFinite && value > 0 ? value : null;
    if (parsed != _parsedCustom) setState(() => _parsedCustom = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocks = ref.watch(sendBlocksProvider);
    final customRate = ref.watch(customFeeRateProvider);
    final feesAsync = ref.watch(bitcoinFeeRatePerBlockProvider);
    final fees = feesAsync.valueOrNull;
    final options = [
      _SpeedOption(
        label: l10n.fast,
        tier: 'fast',
        blocks: 1,
        time: l10n.k10Min,
        icon: Icons.rocket_launch,
        rate: fees?.fastestFee,
      ),
      _SpeedOption(
        label: l10n.standard,
        tier: 'standard',
        blocks: 2,
        time: l10n.k30Min,
        icon: Icons.timer,
        rate: fees?.halfHourFee,
      ),
      _SpeedOption(
        label: l10n.slow,
        tier: 'slow',
        blocks: 3,
        time: l10n.k60Min,
        icon: Icons.directions_walk,
        rate: fees?.hourFee,
      ),
    ];
    final String subtitle;
    if (feesAsync.hasError) {
      subtitle = l10n.feeEstimateUnavailable;
    } else if (fees?.isStale == true) {
      subtitle = l10n.feeRatesStale;
    } else {
      subtitle = l10n.fasterIsMoreExpensiveSlowerIsCheaperButTakesLonger;
    }

    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(title: l10n.networkSpeed, subtitle: subtitle),
            for (final option in options)
              AppBottomSheetListTile(
                title: option.label,
                subtitle: option.rate == null
                    ? option.time
                    : l10n.feeSpeedTimeRate(
                        option.time, _formatRate(option.rate!)),
                icon: option.icon,
                isSelected: customRate == null && blocks == option.blocks,
                onTap: () => _pickSpeed(option),
              ),
            if (feesAsync.hasError) ...[
              SizedBox(height: 4.h),
              AppBottomSheetTextButton(
                text: l10n.retry,
                onPressed: () => ref.invalidate(bitcoinFeeRatePerBlockProvider),
              ),
            ],
            SizedBox(height: 8.h),
            _buildAdvanced(customRate),
            SizedBox(height: 8.h),
            AppBottomSheetTextButton(
              text: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  /// The custom sat/vB rate, the transaction sheet's nerd data pattern:
  /// closed by default so the field stays one tap away without crowding
  /// the three speeds above.
  Widget _buildAdvanced(double? customRate) {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _advancedOpen = !_advancedOpen);
            },
            borderRadius: BorderRadius.circular(10.r),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
              child: Row(
                children: [
                  Icon(
                    _advancedOpen
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18.sp,
                    color: c.textTertiary,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    l10n.advanced,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const Spacer(),
                  if (customRate != null)
                    Text(
                      l10n.customFeeActive(_formatRate(customRate)),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_advancedOpen) ...[
            SizedBox(height: 6.h),
            Text(
              l10n.customFee,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _customController,
                    focusNode: _customFocus,
                    hintText: '15',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: _onCustomChanged,
                    suffixIcon: Padding(
                      padding: EdgeInsets.only(right: 14.w),
                      child: Align(
                        widthFactor: 1,
                        alignment: Alignment.centerRight,
                        child: Text(
                          l10n.satVb,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                SizedBox(
                  width: 92.w,
                  child: AppButton(
                    text: l10n.setLabel,
                    compact: true,
                    onPressed: _parsedCustom == null ? null : _applyCustom,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SpeedOption {
  final String label;
  final String tier;
  final int blocks;
  final String time;
  final IconData icon;
  final double? rate;
  const _SpeedOption({
    required this.label,
    required this.tier,
    required this.blocks,
    required this.time,
    required this.icon,
    required this.rate,
  });
}
