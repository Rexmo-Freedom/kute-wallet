// lib/screens/polymarket/components/live_token_scope.dart
//
// Visibility-scoped CLOB live-price registration for market cards.
//
// Wrap any card that displays live odds in a [LiveTokenScope] carrying the
// card's outcome token ids: the scope registers them with
// [LivePriceNotifier.registerCardTokens] post-frame on mount (mirroring the
// HL market card's watch-set pattern), re-registers when the token set
// changes (e.g. a 5-minute window rolling to new tokens), and unregisters
// on dispose. Registration is refcounted + LRU-capped inside the notifier,
// so an infinite feed's subscription set tracks the viewport instead of
// growing forever — the memory/socket growth fix for the bare `addTokens`
// path.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/polymarket_live_prices_provider.dart';

class LiveTokenScope extends ConsumerStatefulWidget {
  /// Outcome token ids this card renders live prices for. Empty/blank
  /// entries are ignored; the list may change across rebuilds (the scope
  /// diffs and re-registers).
  final List<String> tokens;

  final Widget child;
  final bool keepAlive;

  const LiveTokenScope({
    super.key,
    required this.tokens,
    required this.child,
    this.keepAlive = false,
  });

  @override
  ConsumerState<LiveTokenScope> createState() => _LiveTokenScopeState();
}

class _LiveTokenScopeState extends ConsumerState<LiveTokenScope> {
  List<String> _registered = const [];
  LivePriceNotifier? _heldNotifier;

  /// Root container captured while the element is live — `ref` is
  /// unusable inside [dispose] (Riverpod tears the element's ref down
  /// first; see the identical pattern in `_PolymarketScreenState`).
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync();
    });
  }

  @override
  void didUpdateWidget(covariant LiveTokenScope old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.tokens, widget.tokens) ||
        old.keepAlive != widget.keepAlive) {
      // Post-frame: registration mutates provider state, which is
      // illegal mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sync();
      });
    }
  }

  void _sync() {
    final cleaned =
        widget.tokens.where((t) => t.isNotEmpty).toList(growable: false);
    final notifier = ref.read(livePriceProvider.notifier);
    if (widget.keepAlive && cleaned.isNotEmpty && _heldNotifier == null) {
      notifier.acquire();
      _heldNotifier = notifier;
    } else if ((!widget.keepAlive || cleaned.isEmpty) &&
        _heldNotifier != null) {
      _heldNotifier!.release();
      _heldNotifier = null;
    }
    if (listEquals(_registered, cleaned)) return;
    if (_registered.isNotEmpty) {
      notifier.unregisterCardTokens(_registered);
    }
    if (cleaned.isNotEmpty) {
      notifier.registerCardTokens(cleaned);
    }
    _registered = cleaned;
  }

  @override
  void dispose() {
    if (_registered.isNotEmpty) {
      try {
        _container
            ?.read(livePriceProvider.notifier)
            .unregisterCardTokens(_registered);
      } catch (_) {
        // Container already torn down (full app teardown) — nothing to
        // release.
      }
    }
    _heldNotifier?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(livePriceProvider.notifier);
    return widget.child;
  }
}
