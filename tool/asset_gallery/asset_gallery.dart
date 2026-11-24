// tool/asset_gallery/asset_gallery.dart
//
// Every icon family the app draws, side by side, for comparing the web
// build against the Dart VM (and so the phone): the wallet marks
// (WalletIcon, BrandMark: the 3D Sal face over the pixel SVG), every SVG
// and raster under lib/assets (read from the asset manifest, so a new
// asset shows up on its own), every Sal sprite clip (lib/assets/sal),
// the code-drawn Sal rig and scenes, the icon fonts, and the glass, blur
// and shader surfaces. Each cell has a label; a broken cell is blank or
// shows its fallback.
//
// Two ways to run it, never part of the app:
//
//   * web: `flutter build web --release -t tool/asset_gallery/main.dart
//     -o <dir>` and serve <dir> (the frame meter in the header shows the
//     animation rate);
//   * VM: test/render/asset_gallery_render_test.dart writes the same page
//     as PNGs (`--dart-define=ASSET_GALLERY_RENDER=true`).

import 'dart:async';
import 'dart:convert';

import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icons_plus/src/flag.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_glass.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/theme/app_theme.dart';

/// The wallet marks the Financial hub, the switcher and the account rows
/// draw, one per [WalletVisual.fromWallet] branch.
const List<(String, String, bool, bool, bool)> kGalleryWallets = [
  // label, walletType, hardware, watch-only, signer
  ('Spending (spark)', 'spark', false, false, false),
  ('Bitcoin', 'bitcoin', false, false, false),
  ('Signer', 'spark', false, false, true),
  ('Watch-only', 'generic', false, true, false),
  ('Kute HW', 'kute', true, false, false),
  ('Ledger', 'ledger', true, false, false),
  ('Jade', 'jade', true, false, false),
  ('Passport', 'passport', true, false, false),
  ('SeedSigner', 'seedsigner', true, false, false),
  ('Krux', 'krux', true, false, false),
  ('Keystone', 'keystone', true, false, false),
  ('Generic HW', 'generic', true, false, false),
  ('Legacy HW', 'coldcard', true, false, false),
];

/// Icon-font glyphs the app uses, one per family.
const List<(String, IconData)> kGalleryIconFonts = [
  ('Material wallet', Icons.account_balance_wallet_rounded),
  ('Material bolt', Icons.bolt_rounded),
  ('Material gear', Icons.settings_rounded),
  ('Material star', Icons.star_rounded),
  ('Material eye', Icons.visibility_rounded),
  ('Bootstrap btc', BootstrapIcons.currency_bitcoin),
  ('Bootstrap trophy', BootstrapIcons.trophy_fill),
  ('Bootstrap compass', BootstrapIcons.compass),
  ('Bootstrap cpu', BootstrapIcons.cpu_fill),
  ('Bootstrap bank', BootstrapIcons.bank2),
];

/// The asset paths under lib/assets with [suffix], from the bundle's
/// manifest; empty when it cannot be read.
Future<List<String>> galleryAssets(Iterable<String> suffixes,
    {Iterable<String> skip = const []}) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return [
      for (final a in manifest.listAssets())
        if (a.startsWith('lib/assets/') &&
            suffixes.any(a.endsWith) &&
            !skip.any(a.startsWith))
          a
    ]..sort();
  } catch (_) {
    return const [];
  }
}

/// The Sal manifest's clip names, in its order.
Future<List<String>> gallerySalClips() async {
  try {
    final text = await rootBundle.loadString('$kSalSpriteDir/manifest.json');
    final map = jsonDecode(text);
    if (map is! Map) return const [];
    return [for (final k in map.keys) k as String];
  } catch (_) {
    return const [];
  }
}

/// The whole page. [sections] limits it to some sections (the VM render
/// writes one PNG per section); null shows all of them.
class AssetGallery extends StatefulWidget {
  const AssetGallery(
      {super.key, this.sections, this.svgs, this.rasters, this.clips});

  final Set<String>? sections;

  /// Given by a caller that read them already (the VM render); else read
  /// from the bundle.
  final List<String>? svgs;
  final List<String>? rasters;
  final List<String>? clips;

  static const String wallets = 'wallets';
  static const String svg = 'svg';
  static const String raster = 'raster';
  static const String sal = 'sal';
  static const String rig = 'rig';
  static const String fonts = 'fonts';
  static const String surfaces = 'surfaces';

  @override
  State<AssetGallery> createState() => _AssetGalleryState();
}

class _AssetGalleryState extends State<AssetGallery> {
  List<String> _svgs = const [];
  List<String> _rasters = const [];
  List<String> _clips = const [];

  @override
  void initState() {
    super.initState();
    _svgs = widget.svgs ?? const [];
    _rasters = widget.rasters ?? const [];
    _clips = widget.clips ?? const [];
    if (widget.svgs == null || widget.rasters == null || widget.clips == null) {
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final svgs = await galleryAssets(const ['.svg']);
    final rasters = await galleryAssets(const ['.png', '.gif', '.webp', '.jpg'],
        skip: const ['lib/assets/sal/']);
    final clips = await gallerySalClips();
    if (!mounted) return;
    setState(() {
      _svgs = widget.svgs ?? svgs;
      _rasters = widget.rasters ?? rasters;
      _clips = widget.clips ?? clips;
    });
  }

  final Stopwatch _clock = Stopwatch()..start();
  int? _firstMark;

  bool _on(String s) => widget.sections?.contains(s) ?? true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 10, color: c.textSecondary),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Text('Kute asset gallery · ${kIsWeb ? 'web' : 'VM'}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
              const Spacer(),
              const _FrameMeter(),
            ]),
            // How long the Spending wallet's mark (the 3D Sal's idle face)
            // takes to draw its first frame from a cold start.
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 24,
                child: SalSprite(
                  clip: 'idle',
                  size: 24,
                  fallback: const SizedBox.shrink(),
                  onFrame: (_) {
                    if (_firstMark != null) return;
                    _firstMark = _clock.elapsedMilliseconds;
                    debugPrint('gallery first wallet mark ${_firstMark}ms');
                  },
                ),
              ),
            ),
            if (_on(AssetGallery.wallets)) ...[
              const _Heading('Wallet marks (WalletIcon, BrandMark)'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final w in kGalleryWallets)
                  _Cell(
                    label: w.$1,
                    child: WalletIcon(
                      size: 40,
                      visual: WalletVisual.fromWallet(
                        walletType: w.$2,
                        isHardware: w.$3,
                        isWatchOnly: w.$4,
                        isSigner: w.$5,
                        isDark: context.isDark,
                      ),
                    ),
                  ),
                for (final s in const [20.0, 32.0, 48.0])
                  _Cell(
                      label: 'BrandMark dog $s',
                      child: BrandMark(asset: kuteDogLightAsset, size: s)),
                _Cell(
                    label: 'dog SVG (fallback)',
                    child: SvgPicture.asset(kuteDogAsset(context),
                        width: 32, height: 32)),
              ]),
            ],
            if (_on(AssetGallery.svg)) ...[
              _Heading('SVG assets (${_svgs.length})'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in _svgs)
                  _Cell(
                    label: a.substring('lib/assets/'.length),
                    child: SvgPicture.asset(a,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        placeholderBuilder: (_) =>
                            const SizedBox(width: 40, height: 40)),
                  ),
                for (final f in const [
                  ('flag de', Flags.germany),
                  ('flag gb', Flags.united_kingdom),
                  ('flag pt', Flags.portugal),
                  ('flag us', Flags.united_states_of_america),
                ])
                  _Cell(label: f.$1, child: Flag(f.$2, size: 28)),
              ]),
            ],
            if (_on(AssetGallery.raster)) ...[
              _Heading('Raster assets (${_rasters.length})'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in _rasters)
                  _Cell(
                    label: a.substring('lib/assets/'.length),
                    child: Image.asset(a,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, __) =>
                            Text('ERR', style: TextStyle(color: c.error))),
                  ),
              ]),
            ],
            if (_on(AssetGallery.sal)) ...[
              _Heading('Sal sprite clips (${_clips.length})'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                // level_card_* are @3x-only stills the share card draws
                // at @3x itself (share_card_frame.dart), never a sprite.
                for (final clip in _clips)
                  if (!clip.startsWith('level_card_'))
                    _Cell(
                      label: clip,
                      child: SalSprite(
                        clip: clip,
                        size: 56,
                        loop: true,
                        fallback: SizedBox(
                            width: 56,
                            height: 56,
                            child: Center(
                                child: Text('FAIL',
                                    style: TextStyle(color: c.error)))),
                      ),
                    ),
              ]),
            ],
            if (_on(AssetGallery.rig)) ...[
              const _Heading('Code-drawn Sal (rig and scenes)'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                const _Cell(label: 'KuteDogIdle', child: KuteDogIdle(size: 48)),
                const _Cell(
                    label: 'KuteDogCheer', child: KuteDogCheer(size: 48)),
                const _Cell(
                    label: 'Confirmation',
                    child: KuteDogConfirmation(size: 48)),
                _Cell(
                    label: 'Magnifier',
                    child: KuteDogMagnifier(
                        size: 32,
                        lensColor: c.textPrimary,
                        interval: const Duration(seconds: 1))),
                const _Cell(
                    label: 'Bitcoin',
                    child: KuteDogBitcoin(
                        size: 32, interval: Duration(seconds: 1))),
                const _Cell(
                    label: 'Glance',
                    child: KuteDogGlance(
                        size: 32, interval: Duration(seconds: 1))),
                _Cell(
                    label: 'NotHere',
                    child: KuteDogNotHere(
                        width: 96, ink: c.textPrimary, accent: c.accent)),
                _Cell(
                    label: 'SalAiRing',
                    child: SalAiRing(
                        hues: [c.accent, c.success],
                        interval: const Duration(seconds: 1),
                        child: BrandMark(asset: kuteDogLightAsset, size: 28))),
              ]),
            ],
            if (_on(AssetGallery.fonts)) ...[
              const _Heading('Icon fonts'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final i in kGalleryIconFonts)
                  _Cell(
                      label: i.$1,
                      child: Icon(i.$2, size: 28, color: c.textPrimary)),
              ]),
            ],
            if (_on(AssetGallery.surfaces)) ...[
              const _Heading('Glass, blur and shaders'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Backdrop(
                  label: 'KuteGlass (liquid_glass_widgets)',
                  child: KuteGlass(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.all(12),
                    child: Text('glass',
                        style: TextStyle(color: c.textPrimary, fontSize: 14)),
                  ),
                ),
                _Backdrop(
                  label: 'KuteBlur (BackdropFilter)',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: KuteBlur(
                      sigmaX: 12,
                      sigmaY: 12,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: c.surface.withValues(alpha: 0.3),
                        child: Text('blur',
                            style:
                                TextStyle(color: c.textPrimary, fontSize: 14)),
                      ),
                    ),
                  ),
                ),
                _Cell(
                  label: 'StaleShimmer (ShaderMask)',
                  child: StaleShimmer(
                    stale: true,
                    child: Text('\$1,234.56',
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                _Cell(
                  label: 'ShaderMask gradient',
                  child: ShaderMask(
                    shaderCallback: (r) =>
                        LinearGradient(colors: [c.accent, c.success])
                            .createShader(r),
                    child: const Icon(Icons.auto_awesome_rounded,
                        size: 32, color: Colors.white),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary)),
      );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 104,
      height: 92,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Expanded(child: Center(child: FittedBox(child: child))),
        Text(label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// A busy coloured backdrop for a translucent surface to sit on.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 216,
        height: 92,
        child: Stack(children: [
          Positioned.fill(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final col in const [
                Color(0xFFF7931A),
                Color(0xFF007AFF),
                Color(0xFF34C759),
                Color(0xFFFF3B30),
              ])
                Expanded(child: ColoredBox(color: col)),
            ]),
          ),
          Center(child: child),
          Positioned(
              left: 4,
              bottom: 2,
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 10))),
        ]),
      );
}

/// Frames drawn in the last second (the rate every animation on the page
/// gets).
class _FrameMeter extends StatefulWidget {
  const _FrameMeter();

  @override
  State<_FrameMeter> createState() => _FrameMeterState();
}

class _FrameMeterState extends State<_FrameMeter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final List<Duration> _stamps = [];
  int _fps = 0;
  Duration _logged = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration now) {
    _stamps.add(now);
    while (_stamps.isNotEmpty &&
        now - _stamps.first > const Duration(seconds: 1)) {
      _stamps.removeAt(0);
    }
    if (_stamps.length != _fps) setState(() => _fps = _stamps.length);
    if (now - _logged >= const Duration(seconds: 1)) {
      _logged = now;
      // The web check reads this in the browser console.
      debugPrint('gallery fps $_fps');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_fps fps',
      key: const ValueKey('gallery-fps'),
      style: TextStyle(fontSize: 14, color: context.colors.textPrimary));
}
