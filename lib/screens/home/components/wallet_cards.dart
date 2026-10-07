import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/accessibility.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/services/tracking_service.dart';

/// Identifies which asset card is currently surfaced as the front of the
/// stacked deck. Drives the home background tint (orange/blue/green),
/// makes the Send chip route to the right asset flow, and can be used
/// elsewhere to "act on the active card".
enum WalletCardType { bitcoin, usdc, bank }

/// Hive key for the user's last-foregrounded spending-wallet card.
/// Stored as a stringified [WalletCardType] name so the value survives
/// app restarts (the user's pick of BTC vs USDC on the home stack
/// should persist between sessions).
const String _kSelectedWalletCardHiveKey = 'selectedWalletCard';

WalletCardType _readPersistedWalletCard() {
  try {
    final box = Hive.box('settings');
    final raw = box.get(_kSelectedWalletCardHiveKey);
    if (raw == 'usdc') return WalletCardType.usdc;
    if (raw == 'bank') return WalletCardType.bank;
  } catch (_) {/* box not yet open — fall through to BTC default */}
  return WalletCardType.bitcoin;
}

/// Categorical names for the three balance-privacy levels.
const _kBalancePrivacyStates = ['visible', 'balance_hidden', 'all_hidden'];

/// Advance the balance privacy cycle from a tap on a balance headline and
/// report the change. Every tap is a real change (the cycle always moves
/// one step), so this fires once per tap. States only — never the balance.
void cycleBalancePrivacyTracked(WidgetRef ref, {required String surface}) {
  final from = ref.read(settingsProvider).balancePrivacy % 3;
  final to = (from + 1) % 3;
  TrackingService.track('home_balance_visibility_toggled', params: {
    'from': _kBalancePrivacyStates[from],
    'to': _kBalancePrivacyStates[to],
    'surface': surface,
  });
  ref.read(settingsProvider.notifier).cycleBalancePrivacy();
}

/// Side-effect: persist a new card pick to Hive. Called from
/// `app_widget`'s `ref.listen` so every state mutation is mirrored
/// to disk without each call site having to know about Hive.
Future<void> persistSelectedWalletCard(WalletCardType type) async {
  try {
    final box = await Hive.openBox('settings');
    await box.put(_kSelectedWalletCardHiveKey, type.name);
  } catch (_) {}
}

final selectedWalletCardProvider =
    StateProvider<WalletCardType>((_) => _readPersistedWalletCard());

/// Monzo-style stacked wallet deck. The front card (last in [cards]) is
/// fully visible; back cards peek out from above, slightly scaled down.
/// Tapping a back card animates it to the front and shuffles the current
/// front to a back slot.
class StackedWalletDeck extends StatefulWidget {
  final List<Widget> cards;
  final double peekOffset;
  final double cardHeight;
  // Optional: fired whenever the front card changes. The parent uses
  // this to update selectedWalletCardProvider so ambient chrome (tints,
  // send routing, etc.) can react to which asset is foregrounded.
  final ValueChanged<int>? onFrontChanged;
  // Optional per-card accent colors (parallel to [cards]). The front
  // card gets a border + outer glow in its accent so the selection
  // reads clearly on the card itself, not just behind it.
  final List<Color>? accentColors;

  const StackedWalletDeck({
    super.key,
    required this.cards,
    this.peekOffset = 42.0,
    this.cardHeight = 84.0,
    this.onFrontChanged,
    this.accentColors,
  });

  @override
  State<StackedWalletDeck> createState() => _StackedWalletDeckState();
}

class _StackedWalletDeckState extends State<StackedWalletDeck>
    with SingleTickerProviderStateMixin {
  // Back-to-front order: index 0 is the farthest back, last element is front.
  late List<int> _order;
  // Snapshot of the order before the current in-flight transition starts.
  // Used to interpolate each card between its previous and target slot.
  List<int>? _prevOrder;

  late AnimationController _controller;

  // Mirrors the OS "Reduce Motion" setting. Recomputed every build()
  // (so toggling the setting reflows without restart) and read by
  // _bringToFront, which has no BuildContext of its own. The card
  // reorder slide/lift is decorative transition motion, so when this
  // is true we snap straight to the target order instead of animating.
  bool _reduceMotion = false;

  // Per-card GlobalKeys + measured natural heights. The front card's
  // measured height drives the stack's total height so the sibling
  // widgets below (chip row) reflow when a card expands (e.g. flip to
  // back side / recovery phrase, which is taller than the balance row).
  late List<GlobalKey> _cardKeys;
  final Map<int, double> _measuredHeights = {};
  bool _initialMeasureScheduled = false;

  static const _transitionDuration = Duration(milliseconds: 560);
  static const _depthScaleStep = 0.03;
  static const _liftAmplitude = 0.045;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.cards.length, (i) => i);
    _cardKeys = List.generate(widget.cards.length, (_) => GlobalKey());
    _controller = AnimationController(vsync: this, duration: _transitionDuration);
  }

  @override
  void didUpdateWidget(StackedWalletDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards.length != widget.cards.length) {
      _order = List.generate(widget.cards.length, (i) => i);
      _cardKeys = List.generate(widget.cards.length, (_) => GlobalKey());
      _measuredHeights.clear();
      _prevOrder = null;
      _initialMeasureScheduled = false;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measureCards() {
    if (!mounted) return;
    var changed = false;
    for (int idx = 0; idx < _cardKeys.length; idx++) {
      final ctx = _cardKeys[idx].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final h = box.size.height;
      final prev = _measuredHeights[idx];
      if (prev == null || (prev - h).abs() > 0.5) {
        _measuredHeights[idx] = h;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  void _bringToFront(int cardIdx) {
    if (_controller.isAnimating) return;
    final currentFront = _order.last;
    if (cardIdx == currentFront) return;

    HapticFeedback.lightImpact();
    setState(() {
      _prevOrder = List<int>.from(_order);
      _order = List<int>.from(_order)
        ..remove(cardIdx)
        ..add(cardIdx);
    });
    widget.onFrontChanged?.call(cardIdx);

    // Reduce Motion: skip the slide/lift transition and snap the deck
    // straight to its new order. The reorder itself (which card is
    // front) is the information; the animated travel is decoration.
    if (_reduceMotion) {
      HapticFeedback.selectionClick();
      setState(() => _prevOrder = null);
      return;
    }

    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _prevOrder = null);
    });
  }

  double _scaleForDepth(int depthFromFront) =>
      (1.0 - depthFromFront * _depthScaleStep).clamp(0.86, 1.0);

  @override
  Widget build(BuildContext context) {
    _reduceMotion = reduceMotion(context);
    // Initial measurement after the first layout. Scheduling this only
    // once (instead of on every build) keeps us from piling up
    // post-frame setState()s that can fire while an ancestor
    // LayoutBuilder is still laying out during screen-pop transitions.
    if (!_initialMeasureScheduled) {
      _initialMeasureScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _measureCards();
      });
    }

    // Values are passed in logical pixels (callers typically size via
    // LayoutBuilder + golden ratio, so we don't apply `.h` scaling here).
    final peek = widget.peekOffset;
    final frontIdx = _order.last;
    final frontH = _measuredHeights[frontIdx] ?? widget.cardHeight;
    final totalHeight = (widget.cards.length - 1) * peek + frontH;

    // NotificationListener catches SizeChangedLayoutNotifications bubbling
    // up from each card's SizeChangedLayoutNotifier. That fires on every
    // frame while the front card's internal AnimatedSize (the flip) is
    // ticking, so we re-measure and the wrapping AnimatedSize grows the
    // stack in lockstep with the flip.
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _measureCards();
        });
        return false;
      },
      child: AnimatedSize(
        duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: totalHeight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final rawT = _controller.value;
              // Position eases with a settled curve; the lift on the moving
              // card supplies the "click into place" cadence.
              final posT = Curves.easeInOutCubicEmphasized.transform(rawT);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int pos = 0; pos < _order.length; pos++)
                    _layer(pos, _order[pos], peek, posT, rawT),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _layer(
    int position,
    int cardIdx,
    double peek,
    double posT,
    double rawT,
  ) {
    final isFront = position == _order.length - 1;
    final targetTop = position * peek;
    final targetScale = _scaleForDepth(_order.length - 1 - position);

    double top = targetTop;
    double scale = targetScale;

    final prevOrder = _prevOrder;
    if (prevOrder != null && _controller.isAnimating) {
      final prevPos = prevOrder.indexOf(cardIdx);
      final prevTop = prevPos * peek;
      final prevScale = _scaleForDepth(prevOrder.length - 1 - prevPos);
      top = prevTop + (targetTop - prevTop) * posT;
      scale = prevScale + (targetScale - prevScale) * posT;
    }

    // The card being promoted to the front gets a brief lift: it scales up
    // past its target mid-flight, then settles back. A half-sine peaks at
    // t=0.5, pulled slightly late so the lift crescendos with the slide.
    double lift = 0;
    if (prevOrder != null &&
        _controller.isAnimating &&
        isFront &&
        prevOrder.last != cardIdx) {
      final shifted = (rawT * 0.95 + 0.025).clamp(0.0, 1.0);
      lift = _liftAmplitude * math.sin(math.pi * shifted);
    }

    // Front card gets an accent-colored outer glow so the selection is
    // unmistakable on the card itself (the ambient tint behind is a
    // secondary cue). Back cards stay neutral — they live under a peek
    // so extra chrome would read as noise.
    //
    // IMPORTANT: the AnimatedContainer MUST always be present (not
    // conditionally wrapped), because its child holds a GlobalKey
    // (SizeChangedLayoutNotifier below). Adding/removing the
    // AnimatedContainer between rebuilds reparents the GlobalKey's
    // element — when that reparent collides with an ancestor
    // LayoutBuilder performing layout (e.g. returning from a pushed
    // screen), Flutter asserts "_RenderSizeChangedWithCallback was
    // mutated in _RenderLayoutBuilder.performLayout". Keeping the
    // wrapper stable and toggling the shadow via the decoration keeps
    // the tree shape constant.
    final List<BoxShadow> shadows =
        (isFront && widget.accentColors != null)
            ? [
                BoxShadow(
                  color: widget.accentColors![cardIdx].withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: const Offset(0, 22),
                ),
              ]
            : const <BoxShadow>[];

    // SizeChangedLayoutNotifier posts a SizeChangedLayoutNotification
    // every time its subtree's size changes (including every frame while
    // the card's internal AnimatedSize is animating). The outer listener
    // catches it and re-measures so the stack reflows in real time.
    final Widget contents = AnimatedContainer(
      duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: shadows,
      ),
      child: SizeChangedLayoutNotifier(
        key: _cardKeys[cardIdx],
        child: widget.cards[cardIdx],
      ),
    );

    // Keep the wrapper chain identical between front and back so the
    // inner GlobalKey (on SizeChangedLayoutNotifier) doesn't change
    // parent when the front card flips. GestureDetector with a null
    // onTap is a no-op; AbsorbPointer is toggled by its `absorbing`
    // flag so pointer events pass through when this card is the front.
    final Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFront ? null : () => _bringToFront(cardIdx),
      child: AbsorbPointer(
        absorbing: !isFront,
        child: contents,
      ),
    );

    return Positioned(
      key: ValueKey('stack-card-$cardIdx'),
      top: top,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: scale + lift,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _PinVerificationSheet extends ConsumerStatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onCancelled;

  const _PinVerificationSheet({
    required this.onVerified,
    required this.onCancelled,
  });

  @override
  ConsumerState<_PinVerificationSheet> createState() => _PinVerificationSheetState();
}

class _PinVerificationSheetState extends ConsumerState<_PinVerificationSheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isVerifying = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 24.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    if (_pin.length != 6 || _isVerifying) return;

    setState(() => _isVerifying = true);

    try {
      final authModel = ref.read(authModelProvider);
      final matches = await authModel.pinMatches(_pin);

      if (matches) {
        widget.onVerified();
      } else {
        // Wrong-PIN shake is decorative feedback — the heavy haptic and
        // the cleared dots already convey the failure, so skip the
        // animation under Reduce Motion. Guard the context read behind
        // `mounted` since we're past an await.
        final reduce = mounted &&
            (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
        if (!reduce) {
          _shakeController.forward(from: 0.0);
        }
        HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _isVerifying = false;
        });
      }
    } catch (_) {
      setState(() {
        _pin = '';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
      ),
      child: PlatformSafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 24.h),
            Text(
              context.l10n.enterPinToContinue,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              context.l10n.verifyYourIdentity,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 16.sp,
              ),
            ),
            SizedBox(height: 24.h),

            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: PinProgressIndicator(currentLength: _pin.length),
            ),

            SizedBox(height: 24.h),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: CustomKeypad(
                onDigitPressed: (digit) {
                  if (_pin.length < 6) {
                    HapticFeedback.lightImpact();
                    setState(() => _pin += digit);
                    if (_pin.length == 6) {
                      Future.delayed(const Duration(milliseconds: 100), _verifyPin);
                    }
                  }
                },
                onBackspacePressed: () {
                  if (_pin.isNotEmpty) {
                    HapticFeedback.lightImpact();
                    setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  }
                },
              ),
            ),

            SizedBox(height: 16.h),

            TextButton(
              onPressed: widget.onCancelled,
              child: Text(
                context.l10n.cancel,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }
}

/// Animated red gradient that fades down from the top of the home
/// screen when the active wallet is in savings mode (hardware /
/// watch-only / tracked). Same pulse cadence as the old new-wallet
/// glow but tinted red to read as "you're in a different mode".
class SavingsModeAppTopTint extends ConsumerStatefulWidget {
  const SavingsModeAppTopTint({super.key});

  @override
  ConsumerState<SavingsModeAppTopTint> createState() =>
      _SavingsModeAppTopTintState();
}

class _SavingsModeAppTopTintState extends ConsumerState<SavingsModeAppTopTint>
    with SingleTickerProviderStateMixin {
  // Decorative ambient-warning pulse. NOT auto-repeated here — build()
  // starts the loop only when savings mode is active AND the OS isn't
  // asking us to reduce motion, and stops it otherwise.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final w = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavingsMode = (w?.isHardware ?? false) ||
        (w?.isWatchOnly ?? false) ||
        (w?.isExternalAddress ?? false);
    if (!isSavingsMode) return const SizedBox.shrink();

    // Run the pulse only when motion is allowed; under Reduce Motion
    // the tint stays at a steady (controller value 0) state.
    if (reduce && _glow.isAnimating) {
      _glow.stop();
    } else if (!reduce && !_glow.isAnimating) {
      _glow.repeat(reverse: true);
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _glow,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_glow.value);
          // Softened from 0.32-0.50 → 0.22-0.36. Combined with the
          // shorter envelope below the tint reads as "ambient
          // warning" instead of "screen-wide red wash."
          final peakAlpha = 0.22 + 0.14 * t;
          return Container(
            // Was 180.h — that extended past the header chip and
            // bled into the balance card + action chips when the
            // user scrolled. 100.h covers just the iOS notch + safe
            // area + wallet-switcher chip area, which is where the
            // mode-warning belongs.
            height: 100.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.error.withValues(alpha: peakAlpha),
                  AppColors.error.withValues(alpha: peakAlpha * 0.35),
                  Colors.transparent,
                ],
                // Tightened the decay so most of the alpha lives in
                // the top third — the gradient feels anchored to
                // the status bar rather than smeared down the page.
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

