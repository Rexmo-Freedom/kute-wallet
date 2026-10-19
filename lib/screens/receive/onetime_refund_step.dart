// The return-address step of a one-time receive, a bottom sheet between
// the "Request amount" sheet and the address sheet, over the coin sheet:
// where a deposit that cannot be completed is sent back. The person's own address on the source network, for that coin,
// typed, pasted or scanned in the Send flow's own recipient field. It is
// optional: Skip quotes with no return address (a failed deposit then
// needs Support). Never the wallet's own EVM address, never a Spark or
// Bitcoin address, never filled from the clipboard by itself; the last one
// typed for this wallet and network is filled in. The address never
// reaches analytics: only whether one was set.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/scanned_address.dart'
    show bareRecipientAddress, scanRecipientRaw;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveCaption, ReceiveSheetHeader, kReceiveSheetMaxHeight;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendRecipientError, SendRecipientField;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart' show UsdFlowAction;
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/onetime_refund_address_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// What the return-address step answered: the person's return address,
/// or null when they skipped it.
typedef OneTimeRefundChoice = ({String? address});

/// Asks the return address of a one-time receive of [option] into
/// spark:[destinationAsset], in a sheet over [context]'s (the coin sheet).
/// Null when the person closed it: closing comes back to the coin sheet.
Future<OneTimeRefundChoice?> askOneTimeRefundAddress(
  BuildContext context, {
  required OrchestraReceiveOption option,
  required String destinationAsset,
}) =>
    showAppBottomSheet<OneTimeRefundChoice>(
      context: context,
      builder: (_) => OneTimeRefundSheet(
          option: option, destinationAsset: destinationAsset),
    );

/// The return-address sheet: the Request amount sheet's container and
/// header (the question as its title, the network as its subtitle), the
/// Send flow's recipient field, then Continue or Skip. The keyboard lifts
/// the sheet; the field scrolls when the sheet runs short.
class OneTimeRefundSheet extends ConsumerStatefulWidget {
  const OneTimeRefundSheet({
    super.key,
    required this.option,
    required this.destinationAsset,
  });

  final OrchestraReceiveOption option;
  final String destinationAsset;

  @override
  ConsumerState<OneTimeRefundSheet> createState() => _OneTimeRefundSheetState();
}

class _OneTimeRefundSheetState extends ConsumerState<OneTimeRefundSheet> {
  final _address = TextEditingController();
  late final String? _walletId = ref.read(settingsProvider).activeWalletId;

  bool get _dollars => widget.destinationAsset == kOrchestraUsdAssetCode;

  String get _typed => _address.text.trim();

  bool get _valid => oneTimeRefundAddressValid(widget.option.chain, _typed);

  @override
  void initState() {
    super.initState();
    unawaited(_prefill());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// The last return address typed for this wallet and network, when it
  /// still is one of that network and nothing was typed meanwhile.
  Future<void> _prefill() async {
    final walletId = _walletId;
    if (walletId == null) return;
    final last =
        await OneTimeRefundAddressStore.read(walletId, widget.option.chain);
    if (!mounted ||
        last == null ||
        _address.text.isNotEmpty ||
        !oneTimeRefundAddressValid(widget.option.chain, last)) {
      return;
    }
    setState(() => _address.text = last);
  }

  void _fill(String raw) {
    final bare = bareRecipientAddress(raw);
    setState(() => _address.text = bare);
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty) return;
      _fill(raw);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  Future<void> _scan() async {
    final scanned = await scanRecipientRaw(context);
    if (scanned == null || !mounted) return;
    _fill(scanned);
  }

  /// The step event, with only whether a return address was set.
  void _track(String step, {required bool set}) {
    final props = <String, Object>{
      'asset': widget.option.assetCode,
      'network': widget.option.chain,
      'provider': 'orchestra',
      'destination': oneTimeReceiveDestinationLabel(widget.destinationAsset),
      'address_kind': 'onetime',
      'refund_address_set': set,
    };
    if (_dollars) {
      TrackingService.moneyFlowStep('usd_receive', step, props: props);
    } else {
      TrackingService.moneyFlowStep('receive', step, props: props);
    }
  }

  void _continue() {
    final address = _typed;
    if (!oneTimeRefundAddressValid(widget.option.chain, address)) return;
    final walletId = _walletId;
    if (walletId != null) {
      unawaited(OneTimeRefundAddressStore.save(
          walletId, widget.option.chain, address));
    }
    _track('refund_address_entered', set: true);
    Navigator.of(context).pop<OneTimeRefundChoice>((address: address));
  }

  void _skip() {
    _track('refund_address_skipped', set: false);
    Navigator.of(context).pop<OneTimeRefundChoice>((address: null));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final option = widget.option;
    final typed = _typed;
    final error = typed.isNotEmpty && !_valid
        ? l10n.usdSendAddressWrongNetwork(option.chainDisplayName)
        : null;
    // The coin, its amount, then its return address; the deposit
    // address is next.
    return AppBottomSheetContainer(
      maxHeight: kReceiveSheetMaxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The close X on the left, as on every receive sheet.
          const ReceiveSheetHeader(leading: KuteCloseButton()),
          // The heading and the field give way on a short screen or under
          // the keyboard (the focused field scrolls into view), so the
          // actions below always stay on screen.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppBottomSheetHeader(
                    title: l10n.onetimeRefundTitle,
                    subtitle: l10n.onetimeRefundSubtitle(
                        option.chainDisplayName, option.displaySymbol),
                    showDragHandle: false,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SendRecipientField(
                          key: const ValueKey('onetime-refund-address'),
                          controller: _address,
                          colors: c,
                          hintText: l10n.sendAssetOnNetworkAddressHint(
                              option.displaySymbol, option.chainDisplayName),
                          isValid: _valid,
                          onPaste: () => unawaited(_paste()),
                          onScan: () => unawaited(_scan()),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (error != null) ...[
                          SizedBox(height: 10.h),
                          SendRecipientError(message: error),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UsdFlowAction(
                  label: l10n.continueLabel,
                  onPressed: _valid ? _continue : null,
                  secondaryLabel: l10n.skip,
                  onSecondary: _skip,
                ),
                SizedBox(height: 10.h),
                ReceiveCaption(text: l10n.onetimeRefundSkipNote),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
