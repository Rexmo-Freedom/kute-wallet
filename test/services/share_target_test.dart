// Shared market links (services/share_target.dart): what is parsed, what is
// refused, the referral rules, the park and the router's redirects.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/app_router.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/share_targets.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ShareLinksStore.debugMemory = {};
    ShareTargets.debugReset();
    debugResetShareTargetDedupe();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    ShareLinksStore.debugMemory = null;
    TrackingService.debugTrackObserver = null;
  });

  group('parseLocation', () {
    test('a Predictions event with outcome and code', () {
      final p = ShareTarget.parseLocation(
          Uri.parse('/s/p/bitcoin-above-100k?o=Yes&r=abc123'))!;
      expect(p.target.venue, ShareTargetVenue.predictions);
      expect(p.target.slug, 'bitcoin-above-100k');
      expect(p.target.outcome, 'Yes');
      expect(p.referral, 'ABC123');
    });

    test('an Investing coin, builder dex included', () {
      final p = ShareTarget.parseLocation(Uri.parse('/s/i/xyz:XYZ100'))!;
      expect(p.target.investing, isTrue);
      expect(p.target.slug, 'xyz:XYZ100');
      expect(p.referral, isNull);
    });

    test('refuses wrong venues, shapes and extra segments', () {
      for (final bad in [
        '/s/x/slug',
        '/s/p/',
        '/s/p/Has Spaces',
        '/s/p/UPPER',
        '/s/p/a/b',
        '/s/p/slug%3Cscript%3E',
        '/s/i/BTC?o=Long',
        '/s/i/bad-coin!',
        '/s/p/slug?o=%3Cb%3E',
      ]) {
        expect(ShareTarget.parseLocation(Uri.parse(bad)), isNull, reason: bad);
      }
    });

    test('a referral code of the wrong shape is dropped alone', () {
      for (final code in ['ab', 'TOO-LONG', 'A' * 17, 'x y z', '']) {
        final p = ShareTarget.parseLocation(
            Uri.parse('/s/p/slug').replace(queryParameters: {'r': code}))!;
        expect(p.referral, isNull, reason: code);
      }
    });

    test('not a share location', () {
      expect(ShareTarget.parseLocation(Uri.parse('/usd')), isNull);
      expect(ShareTarget.isShareLocation(Uri.parse('/usd')), isFalse);
    });
  });

  group('links', () {
    test('the shared link carries the market, the outcome and the code', () {
      const t = ShareTarget(
          venue: ShareTargetVenue.predictions,
          slug: 'who-wins',
          outcome: 'Ana B');
      expect(t.link(referralCode: 'k7p2'),
          'https://app.kutewallet.com/#/s/p/who-wins?o=Ana+B&r=K7P2');
      expect(t.link(), 'https://app.kutewallet.com/#/s/p/who-wins?o=Ana+B');
      // An invalid code is never put in the link.
      expect(t.link(referralCode: 'no!'),
          'https://app.kutewallet.com/#/s/p/who-wins?o=Ana+B');
    });

    test('Investing never carries an outcome; nothing else is added', () {
      final t = ShareTarget.of(investing: true, slug: 'BTC', outcome: 'Long')!;
      final link = t.link(referralCode: 'CODE1');
      expect(link, 'https://app.kutewallet.com/#/s/i/BTC?r=CODE1');
      final q = Uri.parse(link.split('#').last).queryParameters.keys;
      expect(q, everyElement(isIn(['o', 'r'])));
    });

    test('a link parses back to its target', () {
      final t = ShareTarget.of(
          investing: false, slug: 'fed-cut-december', outcome: '25 bps')!;
      final fragment = t.link(referralCode: 'ABC').split('#').last;
      final p = ShareTarget.parseLocation(Uri.parse(fragment))!;
      expect(p.target, t);
      expect(p.referral, 'ABC');
    });

    test('encode and decode', () {
      const t = ShareTarget(
          venue: ShareTargetVenue.predictions, slug: 'a-b', outcome: 'x|y');
      expect(ShareTarget.decode(t.encode()), t);
      expect(ShareTarget.decode('garbage'), isNull);
    });
  });

  group('referral store rules', () {
    test('stores a valid code once; the first link keeps the credit', () async {
      expect(await AffiliateService.setPendingReferrerFromShare('abc12'),
          'stored');
      expect(await AffiliateService.setPendingReferrerFromShare('OTHER1'),
          'already_pending');
      expect(await const FlutterSecureStorage().read(key: 'kute_pending_referrer'),
          'ABC12');
    });

    test('refuses a bad shape, the own code and a bound referrer', () async {
      expect(await AffiliateService.setPendingReferrerFromShare('a'), 'invalid');
      FlutterSecureStorage.setMockInitialValues(
          {'kute_affiliate_code': 'MINE1'});
      expect(await AffiliateService.setPendingReferrerFromShare('mine1'),
          'own_code');
      FlutterSecureStorage.setMockInitialValues(
          {'kute_affiliate_referred_by': 'FRIEND'});
      expect(await AffiliateService.setPendingReferrerFromShare('NEW12'),
          'already_bound');
      expect(
          await const FlutterSecureStorage().read(key: 'kute_pending_referrer'),
          isNull);
    });
  });

  group('router', () {
    const link = '/s/p/who-wins?o=Yes&r=ABC12';

    test('no wallet: parked, then splash (or the guest view)', () {
      expect(
          AppRouter.shareLocationRedirect(Uri.parse(link),
              locked: true, hasWallet: false, guestView: false),
          '/splash');
      expect(ShareLinksStore.parkedShareTarget, isNotNull);
      expect(ShareTargets.arrivedThroughShare, isTrue);
      debugResetShareTargetDedupe();
      expect(
          AppRouter.shareLocationRedirect(Uri.parse(link),
              locked: true, hasWallet: false, guestView: true),
          isNull);
    });

    test('locked with a wallet: the PIN first', () {
      expect(
          AppRouter.shareLocationRedirect(Uri.parse(link),
              locked: true, hasWallet: true, guestView: true),
          '/splash');
      final parked = ShareTargets.takeParked()!;
      expect(parked.target.slug, 'who-wins');
      expect(parked.after, 'unlock');
      expect(ShareTargets.hasParked, isFalse);
    });

    test('unlocked: the venue pill, the market on top', () {
      expect(
          AppRouter.shareLocationRedirect(Uri.parse('/s/i/ETH'),
              locked: false, hasWallet: true, guestView: false),
          '/usd?tab=investing');
      expect(ShareTargets.takeParked()!.after, 'link');
    });

    test('a refused link parks nothing and says so once', () {
      expect(
          AppRouter.shareLocationRedirect(Uri.parse('/s/p/BAD SLUG'),
              locked: true, hasWallet: true, guestView: false),
          '/splash');
      AppRouter.shareLocationRedirect(Uri.parse('/s/p/BAD SLUG'),
          locked: true, hasWallet: true, guestView: false);
      expect(ShareTargets.hasParked, isFalse);
      expect(events.where((e) => e.$1 == 'share_target_lost'), hasLength(1));
    });

    test('share_link_opened: categorical, never the code', () async {
      AppRouter.shareLocationRedirect(Uri.parse(link),
          locked: true, hasWallet: false, guestView: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final opened = events.firstWhere((e) => e.$1 == 'share_link_opened').$2!;
      expect(opened['venue'], 'polymarket');
      expect(opened['market'], 'who-wins');
      expect(opened['has_ref'], true);
      expect(opened['wallet_state'], 'none');
      expect(opened.values, isNot(contains('ABC12')));
    });

    test('the root with a code: the code only, then the start', () async {
      expect(
          AppRouter.rootReferralRedirect(Uri.parse('/?r=abc12'), locked: true),
          '/splash');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
          await const FlutterSecureStorage().read(key: 'kute_pending_referrer'),
          'ABC12');
      expect(ShareTargets.hasParked, isFalse);
      expect(AppRouter.rootReferralRedirect(Uri.parse('/usd'), locked: false),
          isNull);
      // A custom-scheme link is the AppsFlyer path's, untouched.
      expect(
          AppRouter.rootReferralRedirect(
              Uri.parse('kute://open?deep_link_value=X'),
              locked: false),
          isNull);
    });
  });
}
