import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/transaction_search_provider.dart';
import 'package:kute/services/tracking_service.dart';

class SearchModal extends ConsumerStatefulWidget {
  const SearchModal({super.key});

  @override
  _SearchModalState createState() => _SearchModalState();
}

class _SearchModalState extends ConsumerState<SearchModal> with AutomaticKeepAliveClientMixin {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _loadUrl();
  }

  void _loadUrl() {
    final searchState = ref.read(transactionSearchProvider);
    final isLiquid = searchState.isLiquid;
    final transactionHash = searchState.txid;
    final unblindedUrl = searchState.unblindedUrl;
    final sparkPaymentId = searchState.sparkPaymentId;

    String uri;
    // `block_explorer_opened` once per mount (initState path): which
    // explorer and whether it opened on a transaction. Never the URL,
    // txid or payment id.
    final String explorer;
    if (sparkPaymentId != null) {
      explorer = 'sparkscan';
    } else if (isLiquid == null || transactionHash == null) {
      explorer = 'mempool';
    } else {
      explorer = isLiquid ? 'liquid' : 'mempool';
    }
    TrackingService.track('block_explorer_opened', params: {
      'explorer': explorer,
      'has_tx': sparkPaymentId != null ||
          (isLiquid != null && transactionHash != null),
    });
    if (sparkPaymentId != null) {
      // SparkScan — strip :0 outpoint suffix if present
      final cleanId = sparkPaymentId.contains(':')
          ? sparkPaymentId.split(':').first
          : sparkPaymentId;
      uri = 'https://sparkscan.io/tx/$cleanId?network=mainnet';
    } else if (isLiquid == null || transactionHash == null) {
      uri = 'https://mempool.space';
    } else if (isLiquid) {
      uri = unblindedUrl == null
          ? 'https://liquid.network/tx/$transactionHash'
          : 'https://liquid.network/$unblindedUrl';
    } else {
      uri = 'https://mempool.space/tx/$transactionHash';
    }

    controller.loadRequest(Uri.parse(uri));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return PlatformSafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          title: Text(
            context.l10n.activityViewOnBlockchain,
            style: TextStyle(color: context.colors.textPrimary),
          ),
          leading: const KuteBackButton(),
        ),
        body: WebViewWidget(
          controller: controller,
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
