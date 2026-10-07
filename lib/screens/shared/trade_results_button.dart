import 'package:kute/screens/shared/trade_notification_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCircleButton;
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/screens/shared/trade_notification_receipt.dart';
import 'package:kute/services/trade_notification_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class TradeResultsButton extends ConsumerWidget {
  final bool onlyUnread;

  /// The round header button (the Financial hub's header): the bell in the
  /// circled chassis of the sheets' header buttons, with the unread badge.
  final bool compact;

  /// Where the hub was opened from, for `trade_notifications_opened`'s
  /// entry_source ('financial_hub'); omitted when not given.
  final String? entrySource;
  const TradeResultsButton(
      {super.key,
      this.onlyUnread = false,
      this.compact = false,
      this.entrySource});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tradeNotificationsProvider);
    final items = state.valueOrNull ?? const <TradeNotification>[];
    final unread = unreadTradeNotificationCount(items);
    if (onlyUnread && unread == 0) return const SizedBox.shrink();
    final button = TextButton.icon(
      icon: Icon(unread > 0
          ? Icons.notifications_active_outlined
          : Icons.notifications_none),
      label: Text(unread > 0
          ? context.l10n.notificationsNewCount(unread)
          : context.l10n.settingsNotifications),
      onPressed: () {
        TrackingService.tradeNotificationsOpened(
            unread: unread, entrySource: entrySource);
        showAppBottomSheet<void>(
          context: context,
          builder: (_) => const _ResultsSheet(),
        );
      },
    );
    if (compact) {
      return KuteCircleButton(
        semanticsLabel: unread > 0
            ? context.l10n.notificationsNewCount(unread)
            : context.l10n.settingsNotifications,
        onPressed: button.onPressed!,
        child: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: Icon(Icons.notifications_none_rounded,
              color: context.colors.textSecondary, size: 22.sp),
        ),
      );
    }
    return onlyUnread ? SafeArea(bottom: false, child: button) : button;
  }
}

/// The notifications list. Opening it marks every receipt it shows read
/// (persisted), so the hub's badge clears once the person has looked and
/// stays clear across restarts; a later receipt brings it back. The rows
/// that were new when the sheet opened keep their dot for this visit.
class _ResultsSheet extends ConsumerStatefulWidget {
  const _ResultsSheet();
  @override
  ConsumerState<_ResultsSheet> createState() => _ResultsSheetState();
}

class _ResultsSheetState extends ConsumerState<_ResultsSheet> {
  /// Receipts that were unread when the sheet opened (or when the list
  /// first loaded, if it was still loading).
  final Set<String> _newOnOpen = {};
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    final items = ref.read(tradeNotificationsProvider).valueOrNull;
    if (items != null) _markSeen(items);
  }

  void _markSeen(List<TradeNotification> items) {
    if (_marked) return;
    _marked = true;
    final unread = items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    _newOnOpen.addAll(unread.map((n) => n.id));
    ref.read(markTradeNotificationsReadProvider)(unread).then((_) {
      if (mounted) ref.invalidate(tradeNotificationsProvider);
    }, onError: (Object _) {/* The badge stays; the list still shows. */});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tradeNotificationsProvider, (_, next) {
      final items = next.valueOrNull;
      if (items != null) _markSeen(items);
    });
    final state = ref.watch(tradeNotificationsProvider);
    final items = state.valueOrNull ?? const <TradeNotification>[];
    final c = context.colors;
    final groups = <DateTime, List<TradeNotification>>{};
    for (final item in [...items]..sort((a, b) => b.time.compareTo(a.time))) {
      final date = DateTime.fromMillisecondsSinceEpoch(item.time);
      groups.putIfAbsent(DateUtils.dateOnly(date), () => []).add(item);
    }
    return AppBottomSheetContainer(
        child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(children: [
        AppBottomSheetHeader(
            title: context.l10n.notificationsSheetTitle,
            trailing: IconButton.outlined(
                tooltip: context.l10n.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded))),
        Expanded(
            child: state.hasError
                ? Center(
                    child: TextButton(
                        onPressed: () =>
                            ref.invalidate(tradeNotificationsProvider),
                        child:
                            Text(context.l10n.notificationsLoadFailedRetry)))
                : state.isLoading && items.isEmpty
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : items.isEmpty
                        ? Center(
                            child: Text(context.l10n.notificationsEmpty))
                        : ListView(
                            padding: EdgeInsets.only(bottom: 24.h),
                            children: groups.entries
                                .map((group) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                              28.w, 12.h, 28.w, 12.h),
                                          child: Text(
                                              DateFormat('MMMM d')
                                                  .format(group.key)
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                  color: c.textSecondary,
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1)),
                                        ),
                                        PremiumGroupContainer(
                                            child: Column(
                                          children: group.value
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            final item = entry.value;
                                            return Column(children: [
                                              buildWalletActivityRow(
                                                leading:
                                                    TradeNotificationArtwork(item: item),
                                                title: Row(children: [
                                                  Expanded(
                                                      child: Text(
                                                          tradeNotificationCopy(
                                                              context.l10n,
                                                              item.title),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              color:
                                                                  c.textPrimary,
                                                              fontSize: 16.sp,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600))),
                                                  if (!item.read ||
                                                      _newOnOpen
                                                          .contains(item.id))
                                                    Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 6.w),
                                                        child: Icon(
                                                            Icons.circle,
                                                            size: 6.sp,
                                                            color: c.accent)),
                                                ]),
                                                subtitle:
                                                    '${item.walletName == null ? '' : '${item.walletName} · '}${tradeNotificationSubtitle(context.l10n, item.subtitle)} · ${DateFormat('MMM d, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.time))}',
                                                amount: tradeNotificationCopy(
                                                    context.l10n,
                                                    item.rows.values
                                                            .firstOrNull ??
                                                        ''),
                                                secondaryAmount:
                                                    tradeNotificationCopy(
                                                        context.l10n,
                                                        item.rows.keys
                                                                .firstOrNull ??
                                                            ''),
                                                amountColor: c.textPrimary,
                                                onTap: () async {
                                                  TrackingService.tradeNotificationTapped(
                                                      product: item.product,
                                                      wasUnread: !item.read ||
                                                          _newOnOpen.contains(
                                                              item.id));
                                                  final l10n = context.l10n;
                                                  final container =
                                                      ProviderScope.containerOf(
                                                          context,
                                                          listen: false);
                                                  final navigator =
                                                      Navigator.of(context,
                                                          rootNavigator: true);
                                                  await TradeNotificationStore
                                                      .markRead(item);
                                                  if (!context.mounted) return;
                                                  ref.invalidate(
                                                      tradeNotificationsProvider);
                                                  navigator.pop();
                                                  openTradeNotificationReceipt(
                                                      navigator: navigator,
                                                      container: container,
                                                      l10n: l10n,
                                                      item: item);
                                                },
                                              ),
                                              if (entry.key <
                                                  group.value.length - 1)
                                                Divider(
                                                    color: c.borderSubtle,
                                                    height: 1,
                                                    indent: 72.w),
                                            ]);
                                          }).toList(),
                                        )),
                                        SizedBox(height: 12.h),
                                      ],
                                    ))
                                .toList())),
      ]),
    ));
  }
}
