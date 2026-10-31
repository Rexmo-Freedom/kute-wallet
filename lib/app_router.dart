import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/bank/bank_screen.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/screens/creation/add_wallet.dart';
import 'package:kute/screens/creation/beta_survey_screen.dart';
import 'package:kute/screens/creation/referrer_code_screen.dart';
import 'package:kute/screens/creation/share_code_screen.dart';
import 'package:kute/screens/pay/components/watch_only_screen.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/screens/creation/confirm_pin.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/shared/bitcoin_transactions_details_screen.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/spash/splash.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/services/share_link_claims.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/home/main_screen.dart';
import 'package:kute/screens/creation/start.dart';
import 'package:kute/screens/settings/components/seed_words.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/creation/recover_choice.dart';
import 'package:kute/screens/creation/recover_wallet.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/screens/recovery/storage_unavailable_screen.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/screens/home/components/search_modal.dart';
import 'package:kute/screens/settings/components/backup_wallet.dart';
import 'package:kute/screens/ledger/ledger_investing_setup_screen.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart';
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/screens/portfolio/wallet_detail_screen.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection;
import 'package:kute/screens/settings/wallets_screen.dart';

import 'package:flutter/material.dart';

import 'package:posthog_flutter/posthog_flutter.dart';

import 'screens/creation/xpub_import_screen.dart';
import 'screens/creation/external_address_import_screen.dart';
import 'screens/shared/spark_transaction_details.dart';
import 'screens/shared/coming_soon_screen.dart';
import 'screens/scanner/scanner_sheet.dart';
import 'screens/settings/affiliate_screen.dart';
import 'screens/app_shell.dart';
import 'services/appsflyer_service.dart';
import 'services/tracking_service.dart';

class AppRouter {
  // The ROOT navigator. The persistent nav shell (KuteTopNavBar) is painted
  // by AppShell as a Positioned overlay ABOVE the branch navigators, so any
  // full-screen sub-screen (Receive, Settings, the send flow, …) that pushes
  // on a branch navigator would render UNDER the nav bar. Giving those
  // sub-routes `parentNavigatorKey: _rootNavigatorKey` pushes them on THIS
  // navigator instead — full-screen, OVER the shell (nav bar hidden), exactly
  // as before the nav shell landed. Only the 4 tab roots (/home, /bank,
  // /hyperliquid, /polymarket) stay inside the shell.
  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  /// The root navigator's key, for a layer drawn outside it (the shell bar)
  /// and for services that show a sheet with no widget of their own (the
  /// share-link pay prompt on resume).
  static GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

  // Per-branch navigator keys for the persistent nav shell. Each tab
  // (Home / Bank / USD / Trading / Predictions) owns its own Navigator so a
  // sub-route pushed within a branch (e.g. /home/pay/confirm_send) stacks
  // and pops inside that branch, and switching tabs preserves each branch's
  // own navigation stack.
  static final GlobalKey<NavigatorState> _homeBranchKey =
      GlobalKey<NavigatorState>(debugLabel: 'homeBranch');
  static final GlobalKey<NavigatorState> _bankBranchKey =
      GlobalKey<NavigatorState>(debugLabel: 'bankBranch');
  static final GlobalKey<NavigatorState> _usdBranchKey =
      GlobalKey<NavigatorState>(debugLabel: 'usdBranch');
  static final GlobalKey<NavigatorState> _tradingBranchKey =
      GlobalKey<NavigatorState>(debugLabel: 'tradingBranch');
  static final GlobalKey<NavigatorState> _predictionsBranchKey =
      GlobalKey<NavigatorState>(debugLabel: 'predictionsBranch');

  /// A pushed screen's transition (founder, 31 October 2026, after
  /// Orchestra): in on the settle easing with a subtle 0.97 → 1 scale and
  /// a fade, back on the sheets' close easing; a plain line under Reduce
  /// Motion. The numbers live in lib/theme/kute_motion.dart.
  static CustomTransitionPage<void> _buildFadeScalePage({
    required Widget child,
    required GoRouterState state,
    Duration duration = KuteMotion.settleDuration,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      // Carry the GoRoute's name onto the page so NavigatorObservers
      // (SyncRouteObserver / PostHog) see it — without this every
      // route.settings.name was null and the route-gated background
      // sync never knew which screen the user was on.
      name: state.name,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final isPush = animation.status == AnimationStatus.forward;

        final reduce = KuteMotion.reduce(context);
        final curve = reduce
            ? Curves.linear
            : (isPush ? KuteMotion.settle : KuteMotion.sheetOut);

        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: curve,
        );

        final scaleAnimation =
            Tween<double>(begin: reduce ? 1.0 : 0.97, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: curve,
          ),
        );

        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }

  // ── deep_link_opened bookkeeping (analytics only) ──
  // First router creation ≈ process start (RestartWidget rebuilds keep it).
  static DateTime? _firstRouterAt;
  // Set once any deep link has been handled: later links are warm.
  static bool _deepLinkHandled = false;
  // go_router can evaluate the top-level redirect more than once for the
  // same incoming URI; the hash + timestamp dedupe those re-evaluations.
  // A hash, not the URI, so the referral code isn't kept around.
  static int? _lastDeepLinkHash;
  static DateTime? _lastDeepLinkAt;

  /// Fires `deep_link_opened` once per incoming absolute URI. Categorical
  /// only: never the URI, host, path, query or referral code. The link's
  /// utm_* values (and nothing else) become person properties.
  static void _trackDeepLink(Uri uri) {
    final now = DateTime.now();
    final hash = uri.toString().hashCode;
    final lastAt = _lastDeepLinkAt;
    if (hash == _lastDeepLinkHash &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastDeepLinkHash = hash;
    _lastDeepLinkAt = now;
    final startedAt = _firstRouterAt;
    final wasColdStart = !_deepLinkHandled &&
        startedAt != null &&
        now.difference(startedAt) < const Duration(seconds: 15);
    _deepLinkHandled = true;
    final scheme = uri.scheme.toLowerCase();
    TrackingService.deepLinkOpened(
      linkType: scheme == 'http' || scheme == 'https'
          ? 'universal_link'
          : 'custom_scheme',
      wasColdStart: wasColdStart,
    );
    // Campaign attribution: only the link's utm_* values, as person
    // properties.
    TrackingService.captureUtmFromUri(uri);
  }

  /// What the top-level redirect does with an incoming absolute URI:
  /// analytics (one `deep_link_opened` plus the utm_* person properties)
  /// and the referral code. Never navigates.
  @visibleForTesting
  static void handleIncomingLink(Uri uri) {
    _trackDeepLink(uri);
    // A claim link (`/c/{id}`, or `deep_link_value=claim`) carries no
    // referral code: `claim` must never be bound as one.
    if (ShareLinkClaims.claimIdFromLink(uri) == null) {
      AppsFlyerService.ingestReferrerFromDeepLink(
        uri.queryParameters['deep_link_value'] ??
            uri.queryParameters['af_sub1'] ??
            uri.queryParameters['c'],
      );
    }
    // Website → app identity link (never a referral code).
    AppsFlyerService.ingestWebVisitorFromDeepLink(
        uri.queryParameters['af_sub2']);
  }

  /// The routes reachable while no session is unlocked: the cold-start
  /// chain (splash → start | restore_secrets | storage_unavailable |
  /// open_pin, and storage_unavailable back to splash) and PIN setup,
  /// which onboarding and the restore flow reach before a session
  /// exists (confirm_pin unlocks the session before going anywhere
  /// else). Everything else (money, seeds, settings) needs the session.
  @visibleForTesting
  static const Set<String> lockedAllowlist = {
    '/splash',
    '/start',
    '/open_pin',
    '/set_pin',
    '/confirm_pin',
    '/restore_secrets',
    '/storage_unavailable',
  };

  /// Where a navigation to [location] goes while [locked]: nowhere else
  /// when the location is allowed, splash otherwise (splash re-runs the
  /// cold-start classification and lands on the PIN screen). Never
  /// redirects an unlocked session.
  @visibleForTesting
  static String? lockRedirect({required bool locked, required String location}) {
    if (!locked) return null;
    return lockedAllowlist.contains(Uri.parse(location).path) ? null : '/splash';
  }

  /// Where an incoming share-link claim (`https://<web>/c/{id}`, or a
  /// OneLink with `deep_link_value=claim&deep_link_sub1={id}`) goes: the
  /// Claim screen when the session is unlocked; while [locked] (a cold
  /// start, a fresh install still onboarding) the id is parked
  /// (ShareLinksStore) and the Claim screen opens once the session is
  /// unlocked (app_widget.dart). Null for every other URI.
  @visibleForTesting
  static String? claimLinkRedirect(Uri uri, {required bool locked}) {
    final id = ShareLinkClaims.claimIdFromLink(uri);
    if (id == null) return null;
    if (!locked) return ShareLinkClaims.claimRoutePath(id);
    ShareLinksStore.parkClaim(id);
    return null;
  }

  /// The top-level redirect. [sessionLocked] reads the session (null
  /// `sessionAuthProvider`); [initialRoute] seeds the last good location.
  ///
  /// Affiliate deep links arrive as ABSOLUTE URIs — the custom scheme
  /// (kute://open?deep_link_value=CODE) on Android and either that or the
  /// AppsFlyer Universal Link (https://kute.onelink.me/...?deep_link_value=CODE)
  /// on iOS. go_router has no route for them, so without this it renders a
  /// "Page Not Found". We instead register the referral code app-side (works
  /// in debug + release, both platforms — no SDK round-trip needed) and send
  /// the user right back to where they were. Regular in-app navigation uses
  /// relative paths (no scheme), so it's untouched.
  ///
  /// While locked, any location off [lockedAllowlist] (a deep link into a
  /// money or seed route, a stale stack after a wipe) goes to splash.
  @visibleForTesting
  static GoRouterRedirect redirectFor({
    required bool Function() sessionLocked,
    required String initialRoute,
  }) {
    // Last in-app location we sat on, so an incoming deep link can register its
    // referral code without yanking the user off their current screen.
    var lastGood = initialRoute;
    return (context, state) {
      final uri = state.uri;
      if (uri.hasScheme) {
        handleIncomingLink(uri);
        return claimLinkRedirect(uri, locked: sessionLocked()) ??
            lockRedirect(locked: sessionLocked(), location: lastGood) ??
            lastGood;
      }
      final guard = lockRedirect(
          locked: sessionLocked(), location: state.matchedLocation);
      if (guard != null) return guard;
      lastGood = state.matchedLocation;
      return null;
    };
  }

  static GoRouter createRouter(
    String initialRoute, {
    required bool Function() sessionLocked,
    List<NavigatorObserver> extraObservers = const [],
  }) {
    _firstRouterAt ??= DateTime.now();
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: initialRoute,
      // PostHog's `PosthogObserver` is wired in `app_widget.dart` via
      // `extraObservers`. Firebase Analytics' routeObserver is gone;
      // legacy `TrackingService.routeObserver` is now a no-op.
      observers: [...extraObservers],
      redirect:
          redirectFor(sessionLocked: sessionLocked, initialRoute: initialRoute),
      routes: [
        GoRoute(
          path: '/splash',
          name: 'splash',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const Splash(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/claim/:id',
          name: ClaimScreen.routeName,
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: ClaimScreen(id: state.pathParameters['id'] ?? ''),
            state: state,
          ),
        ),
        GoRoute(
          path: '/start',
          name: 'start',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const Start(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/transaction-details',
          name: 'transactionDetails',
          pageBuilder: (context, state) {
            final transaction = state.extra as BitcoinTransaction;
            return _buildFadeScalePage(
              child: BitcoinTransactionDetailsScreen(transaction: transaction),
              state: state,
            );
          },
        ),

        GoRoute(
          path: '/spark-transaction-details',
          name: 'sparkTransactionDetails',
          pageBuilder: (context, state) {
            return _buildFadeScalePage(
              child: SparkTransactionDetails(),
              state: state,
            );
          },
        ),
        GoRoute(
          path: '/seed_words',
          name: 'seed_words',
          // PostHogMaskWidget: defense-in-depth. Replay is OFF in both
          // the Dart PostHogConfig and the platform manifests, but
          // wrapping seed display here means a future replay flip
          // can't accidentally capture the mnemonic mid-deploy.
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const PostHogMaskWidget(child: SeedWords()),
            state: state,
          ),
        ),
        GoRoute(
          path: '/open_pin',
          name: 'open_pin',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const OpenPin(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/confirm_pin',
          name: 'confirm_pin',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ConfirmPin(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/passkey_choice',
          name: 'passkey_choice',
          pageBuilder: (context, state) {
            final next = (state.extra as String?) ?? '/home';
            return _buildFadeScalePage(
              child: PasskeyChoice(nextRoute: next),
              state: state,
            );
          },
        ),
        GoRoute(
          path: '/beta_survey',
          name: 'beta_survey',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const BetaSurveyScreen(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/referrer_code',
          name: 'referrer_code',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ReferrerCodeScreen(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/share_code',
          name: 'share_code',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ShareCodeScreen(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/wallet_creation',
          name: 'wallet_creation',
          redirect: (_, __) => '/home',
        ),
        GoRoute(
          path: '/set_pin',
          name: 'set_pin',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const SetPin(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          // Optional deep-link key via `extra` (e.g. unified search's
          // `context.push('/settings', extra: 'currency')`) auto-opens
          // that setting's action. Bare gear tap pushes no extra →
          // null → normal Settings with nothing auto-opened.
          pageBuilder: (context, state) {
            final extra = state.extra as String?;
            return _buildFadeScalePage(
              child: Settings(initialActionKey: extra),
              state: state,
            );
          },
        ),
        GoRoute(
          path: '/camera',
          name: 'camera',
          redirect: (_, __) => '/smart-scanner',
        ),
        // ── Persistent nav shell ─────────────────────────────────────────
        // The nav tabs (Home / Bank / USD / Trading / Predictions) live
        // inside ONE StatefulShellRoute so a single KuteTopNavBar stays
        // mounted across them (the pill morphs for real) and the branch
        // pages SWIPE horizontally. The navigatorContainerBuilder lays the
        // branch navigators out in a PageView (see AppShell). Branch ORDER
        // matches AppShell's _kShellTabs: 0=Home, 1=Bank (/bank, hidden),
        // 2=USD (/usd), 3=Trading (/hyperliquid),
        // 4=Predictions (/polymarket).
        // Every other top-level route (/settings, /affiliate, …)
        // stays OUTSIDE the shell and pushes full-screen over it,
        // exactly as before.
        StatefulShellRoute(
          navigatorContainerBuilder: (context, navigationShell, children) =>
              AppShell(navigationShell: navigationShell, children: children),
          // The shell's own page carries no transition — swapping to the
          // shell (from splash / onboarding) shouldn't fade/scale; the tabs
          // inside it swipe instead.
          pageBuilder: (context, state, navigationShell) => NoTransitionPage(
            key: state.pageKey,
            child: navigationShell,
          ),
          branches: [
            // ── Branch 0: Home (+ its full sub-route tree) ──
            StatefulShellBranch(
              navigatorKey: _homeBranchKey,
              routes: [
                GoRoute(
                  path: '/home',
                  name: 'home', // Already named
                  // Bottom-nav tab destination. NoTransitionPage so the branch
                  // root paints instantly; tab-switching is now a swipe.
                  // Detail/sub-routes off /home still keep the fade-scale below.
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    key: state.pageKey,
                    child: const MainScreen(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'pay', // Corrected to relative path
                      name: 'pay',
                      // Escape the home-branch navigator onto the ROOT navigator so
                      // the send flow renders full-screen OVER the shell (no nav
                      // bar). `pay` itself only redirects — its children
                      // (watch-only-signing, confirm_send) inherit this navigator.
                      parentNavigatorKey: _rootNavigatorKey,
                      redirect: (context, state) {
                        if (state.extra is! String) return null;

                        final asset = (state.extra as String).toLowerCase();
                        switch (asset) {
                          // Both legacy 'bitcoin' / 'lightning' deep-link
                          // assets resolve to the unified send. The send
                          // stepper handles wallet-type branching internally
                          // (Spark for hot, BDK PSBT for hardware/watch-only).
                          case 'bitcoin':
                          case 'lightning':
                            return state.namedLocation('pay_send');
                        }
                        return null;
                      },
                      routes: [
                        GoRoute(
                          path: 'watch-only-signing',
                          name: 'watchOnlySigning',
                          parentNavigatorKey: _rootNavigatorKey,
                          pageBuilder: (context, state) {
                            final extras = state.extra as Map<String, dynamic>;
                            return _buildFadeScalePage(
                              child: WatchOnlySigningScreen(
                                psbtBase64: extras['psbtBase64'] as String,
                                walletType: extras['walletType'] as String,
                                scriptType: extras['scriptType'] as String?,
                                // Source wallet id — optional, used by the
                                // screen to fingerprint-fix + tag fee logs
                                // against the SOURCE wallet rather than the
                                // carousel-pinned active wallet.
                                walletId: extras['walletId'] as String?,
                              ),
                              state: state,
                            );
                          },
                        ),
                        GoRoute(
                          path: 'confirm_send',
                          name: 'pay_send',
                          parentNavigatorKey: _rootNavigatorKey,
                          // The send sheet (send_sheet.dart): every way
                          // in (the dock, the scanner hand-off, payment
                          // links) opens it over the screen it came
                          // from; a preset recipient opens it full.
                          pageBuilder: (context, state) => SendSheetPage<void>(
                            key: state.pageKey,
                            name: state.name,
                            child: const ConfirmSend(),
                          ),
                        ),
                        // Legacy aliases — keep `pay_bitcoin` and
                        // `pay_spark_bitcoin` resolving to the unified send
                        // route so any cached deep links / push notifications
                        // landing here from older builds still work. Drop on
                        // a future migration once we're sure no caller pushes
                        // these names directly.
                        GoRoute(
                          path: 'confirm_bitcoin_payment',
                          name: 'pay_bitcoin',
                          redirect: (_, __) => '/home/pay/confirm_send',
                        ),
                        GoRoute(
                          path: 'confirm_spark_bitcoin_payment',
                          name: 'pay_spark_bitcoin',
                          redirect: (_, __) => '/home/pay/confirm_send',
                        ),
                      ],
                    ),
                    // The Bitcoin receive. The dock opens it as a sheet
                    // (receive_sheet.dart); this route stays for deep
                    // links and opens that same sheet over the current
                    // screen.
                    GoRoute(
                      path: '/receive',
                      name: kBitcoinReceiveRouteName,
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (context, state) => ReceiveSheetPage(
                        key: state.pageKey,
                        name: state.name,
                        usd: false,
                      ),
                    ),
                    // The Dollars tab's own Receive
                    // (usd_receive_screen.dart), the twin of the dollar
                    // send: the coin the user picks is converted on the
                    // way in, and it is the dollars that land. Like the
                    // Bitcoin one it opens as a sheet; this route stays
                    // for deep links (and the Investments deposit's
                    // Receive row) and opens that same sheet. Every way
                    // in opens its coin step; an old `?coin=auto` link
                    // is accepted and ignored.
                    GoRoute(
                      path: '/receive_dollars',
                      name: kUsdReceiveRouteName,
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (context, state) => ReceiveSheetPage(
                        key: state.pageKey,
                        name: state.name,
                        usd: true,
                      ),
                    ),
                    GoRoute(
                      path: '/add_wallet',
                      name: 'addWallet',
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (context, state) => _buildFadeScalePage(
                        child: const AddWallet(),
                        state: state,
                      ),
                    ),
                    GoRoute(
                      path: '/import-xpub',
                      name: 'importXpub',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => const XPubImportScreen(),
                    ),
                    GoRoute(
                      path: '/import-external-address',
                      name: 'importExternalAddress',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) =>
                          const ExternalAddressImportScreen(),
                    ),
                    GoRoute(
                      path: '/wallet/:walletId',
                      name: 'walletDetail',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => WalletDetailScreen(
                        walletId: state.pathParameters['walletId']!,
                        // Opened from a pending Ledger settlement in Activity
                        // detail (Phase 5 plan B13).
                        ledgerAccountView:
                            state.uri.queryParameters['view'] == 'ledger',
                      ),
                    ),
                    // Ledger investing setup (Wallet hardening Phase 4, P4.3). Reached
                    // after a Ledger import and from the Ledger account screen's
                    // "Enable investing", both behind kLedgerInvestingEnabled.
                    GoRoute(
                      path: '/ledger/:walletId/investing-setup',
                      name: 'ledgerInvestingSetup',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => LedgerInvestingSetupScreen(
                        walletId: state.pathParameters['walletId']!,
                        fromImport:
                            state.uri.queryParameters['from'] == 'import',
                      ),
                    ),
                    // The scanner opens as a sheet (scanner_sheet.dart);
                    // this route stays as a thin wrapper for links and
                    // opens that same sheet, joining animated codes.
                    GoRoute(
                      path: '/qr-scanner',
                      name: 'QrScanner',
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (context, state) => ScannerSheetPage<String>(
                        key: state.pageKey,
                        name: state.name,
                        mode: ScannerMode.multiPart,
                      ),
                    ),
                    GoRoute(
                      path: 'settings',
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (context, state) => _buildFadeScalePage(
                        child: const Settings(),
                        state: state,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // ── Branch 1: Bank (coming soon placeholder page) ──
            StatefulShellBranch(
              navigatorKey: _bankBranchKey,
              routes: [
                GoRoute(
                  path: '/bank',
                  name: 'bank',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    key: state.pageKey,
                    child: const BankScreen(),
                  ),
                ),
              ],
            ),
            // ── Branch 2: USD (the spending account's dollars) ──
            // Occupies the strip slot the hidden Bank tab used to hold.
            StatefulShellBranch(
              navigatorKey: _usdBranchKey,
              routes: [
                GoRoute(
                  path: '/usd',
                  name: 'usd',
                  // `?tab=investing|predictions|positions` (what the venue
                  // routes redirect to) or `extra: {'tab': …}` picks the
                  // Investments pill (an old `earn` link opens the default
                  // pill: Earn is shown nowhere; a Portfolio section's or
                  // an old Portfolio tab's key opens the Portfolio pill on
                  // that section, see PortfolioSection.forLink); nothing
                  // keeps the pill where it was. The page updates in place on a new
                  // link (same pageKey), and the screen applies it then.
                  pageBuilder: (context, state) {
                    final extra = state.extra;
                    final tab = state.uri.queryParameters['tab'] ??
                        (extra is Map ? extra['tab'] as String? : null);
                    return NoTransitionPage<void>(
                      key: state.pageKey,
                      child: UsdAccountScreen(
                          initialTab: InvestmentsTab.fromKey(tab),
                          initialSection: PortfolioSection.forLink(tab)),
                    );
                  },
                ),
              ],
            ),
            // ── Branch 3: Trading (Hyperliquid) ──
            StatefulShellBranch(
              navigatorKey: _tradingBranchKey,
              routes: [
                GoRoute(
                  path: '/hyperliquid',
                  name: 'hyperliquid',
                  // For the spending account Investing is a pill of the
                  // Investments tab: the link lands on /usd with that
                  // pill (one balance; no venue deposit exists, so the
                  // old `extra: 'deposit'` auto-open is gone). A Ledger
                  // owner keeps its own branch.
                  redirect: (context, _) =>
                      spendingVenueRedirect(context, InvestmentsTab.investing),
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    key: state.pageKey,
                    // The Ledger's own Hyperliquid tab when a Ledger
                    // wallet owns the first tab; empty otherwise.
                    child: const ShellTradingTab(),
                  ),
                ),
              ],
            ),
            // ── Branch 4: Predictions (Polymarket) ──
            StatefulShellBranch(
              navigatorKey: _predictionsBranchKey,
              routes: [
                GoRoute(
                  path: '/polymarket',
                  name: 'polymarket',
                  // See /hyperliquid: the spending account's Predictions
                  // is a pill of the Investments tab.
                  redirect: (context, _) => spendingVenueRedirect(
                      context, InvestmentsTab.predictions),
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    key: state.pageKey,
                    // The Ledger's own Polymarket tab when a Ledger
                    // wallet owns the first tab; empty otherwise.
                    child: const ShellPredictionsTab(),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/smart-scanner',
          name: 'smartScanner',
          // Every Scan in the app opens the scanner sheet directly
          // (showRoutingScannerSheet / showScannerSheet); this route stays
          // as a thin wrapper for links and opens that same sheet over
          // the current screen. `extra: {'returnRaw': true}` closes with
          // the scanned string instead of routing it.
          pageBuilder: (context, state) {
            final extra = state.extra;
            final returnRaw = extra is Map && extra['returnRaw'] == true;
            return ScannerSheetPage<String>(
              key: state.pageKey,
              name: state.name,
              mode: returnRaw ? ScannerMode.recipient : ScannerMode.route,
            );
          },
        ),
        // The legacy standalone '/bank' coming-soon route was removed: Bank
        // is a real shell branch now (branch 1), and two GoRoutes claiming
        // the same path made which screen you land on order-dependent.
        GoRoute(
          path: '/affiliate',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const AffiliateScreen(),
            state: state,
          ),
        ),
        // The Portfolio, its own screen over the shell (founder, 31 October
        // 2026): the Dollars action row's third button, and where every
        // old `/usd?tab=portfolio|positions|orders|activity…` link lands
        // (portfolio_screen.dart).
        GoRoute(
          path: PortfolioScreen.route,
          name: 'portfolio',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const PortfolioScreen(),
            state: state,
          ),
        ),
        // The '/earn' route is gone: the Flashnet USDB Earn product was
        // removed (user decision), the same way Morpho went before it.
        GoRoute(
          path: '/card/topup',
          name: 'coming_soon_card_topup',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'Card Top Up',
              analyticsKey: 'card_top_up',
              icon: Icons.credit_card_rounded,
              color: Color(0xFF9D4EDD),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/fiat/deposit',
          name: 'coming_soon_eur_deposit',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'Euro Deposit',
              analyticsKey: 'euro_deposit',
              icon: Icons.euro_symbol_rounded,
              color: Color(0xFF3266CC),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/fiat/withdraw',
          name: 'coming_soon_eur_withdraw',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'Euro Withdrawal',
              analyticsKey: 'euro_withdrawal',
              icon: Icons.euro_symbol_rounded,
              color: Color(0xFF3266CC),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/sell',
          name: 'coming_soon_sell',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'Sell Bitcoin',
              analyticsKey: 'sell_bitcoin',
              icon: Icons.sell_rounded,
              color: Color(0xFFEF4444),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/games',
          name: 'coming_soon_games',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'Games',
              analyticsKey: 'games',
              icon: Icons.sports_esports_rounded,
              color: Color(0xFFFF6B00),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/ai',
          name: 'coming_soon_ai',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const ComingSoonScreen(
              title: 'AI',
              analyticsKey: 'ai',
              icon: Icons.auto_awesome_rounded,
              color: Color(0xFF8B5CF6),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/recover_wallet',
          name: 'recover_wallet',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const RecoverChoiceScreen(),
            state: state,
          ),
          routes: [
            GoRoute(
              path: 'seed',
              name: 'recover_wallet_seed',
              // Masked: seed-phrase entry surface.
              pageBuilder: (context, state) => _buildFadeScalePage(
                child: const PostHogMaskWidget(child: RecoverWallet()),
                state: state,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/search_modal',
          name: 'search_modal',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const SearchModal(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/backup_wallet',
          name: 'backup_wallet',
          // Masked: backup reveal shows the mnemonic. Most critical
          // surface to keep out of any future replay capture.
          pageBuilder: (context, state) => _buildFadeScalePage(
            // Optional walletId via `extra` lets callers pin the
            // backup screen to a specific wallet's mnemonic without
            // first flipping the carousel-active wallet.
            child: PostHogMaskWidget(
                child: BackupWallet(walletId: state.extra as String?)),
            state: state,
          ),
        ),
        GoRoute(
          path: '/restore_secrets',
          name: 'restore_secrets',
          // Masked: recovery phrase entry surface.
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: PostHogMaskWidget(
              child: RestoreSecretsScreen(
                reason: state.extra is RestoreSecretsReason
                    ? state.extra as RestoreSecretsReason
                    : RestoreSecretsReason.walletUnavailable,
              ),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/storage_unavailable',
          name: 'storage_unavailable',
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: StorageUnavailableScreen(
              result: state.extra is StorageBootResult
                  ? state.extra as StorageBootResult
                  : const StorageBootResult(
                      StorageBootState.storageUnavailable),
            ),
            state: state,
          ),
        ),
        GoRoute(
          path: '/wallets',
          name: 'wallets',
          // Masked: reveals recovery phrases and public keys.
          pageBuilder: (context, state) => _buildFadeScalePage(
            child: const PostHogMaskWidget(child: WalletsScreen()),
            state: state,
          ),
        ),
      ],
    );
  }
}
