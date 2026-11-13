// lib/screens/shared/send/send_branta_payee.dart
//
// THE PAYEE BRANTA NAMES, on Send's existing cards
// (services/branta/branta_payee_service.dart; founder, 12 November 2026).
// Nothing new on screen: a verified payee wears its logo in the avatar's
// own circle (the rail's mark until the logo has loaded, and if it never
// does: the circle never changes size), its name where the name goes and
// one quiet line, "Verified by Branta", in the cards' secondary style with
// the success tick the resolved row already draws. An unverified
// destination looks exactly as before. A swapped address is the one
// warning, in the inline error style.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/branta/branta_payee_records.dart'
    show brantaLogoCacheManager;
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The payee Branta names for [destination] paid on [rail]: null while it
/// is looked up, when there is nothing to show, and when [rail] is null
/// (a destination Branta has nothing for).
BrantaPayee? watchBrantaPayee(
    WidgetRef ref, String destination, BrantaRail? rail) {
  final d = destination.trim();
  if (rail == null || d.isEmpty) return null;
  return ref
      .watch(brantaPayeeProvider((destination: d, rail: rail)))
      .valueOrNull;
}

/// The payee's logo, [size] across, clipped to the avatar's circle;
/// [fallback] (the rail's mark) until it loads and whenever it cannot.
/// Drawn from [brantaLogoCacheManager]'s disk cache: Send's lookup and the
/// activity rows of a stored payee (branta_payee_records.dart) share it.
class BrantaPayeeLogo extends StatelessWidget {
  const BrantaPayeeLogo({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String? url;
  final double size;
  final Widget fallback;

  /// Tests and renders draw the logo from memory instead of the network.
  @visibleForTesting
  static ImageProvider Function(String url)? debugImageProvider;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final Widget logo;
    if (u == null || u.isEmpty) {
      logo = fallback;
    } else if (debugImageProvider case final provider?) {
      logo = ClipOval(
        child: Image(
          image: provider(u),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Center(child: fallback),
        ),
      );
    } else {
      logo = ClipOval(
        child: CachedNetworkImage(
          imageUrl: u,
          // On disk with the payment's stored payee, so the activity rows
          // and the receipt draw it without a download (and offline).
          cacheManager: brantaLogoCacheManager,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth:
              (size * MediaQuery.of(context).devicePixelRatio).round(),
          placeholder: (_, __) => Center(child: fallback),
          errorWidget: (_, __, ___) => Center(child: fallback),
        ),
      );
    }
    return SizedBox.square(
      key: const ValueKey('send-branta-logo'),
      dimension: size,
      child: Center(child: logo),
    );
  }
}

/// "Verified by Branta", with the resolved row's success tick, in the
/// cards' secondary line style.
class SendVerifiedByBranta extends StatelessWidget {
  const SendVerifiedByBranta({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const ValueKey('send-branta-verified'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 14.sp, color: c.success),
        SizedBox(width: 4.w),
        Flexible(
          child: Text(
            context.l10n.sendVerifiedByBranta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
