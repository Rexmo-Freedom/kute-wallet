import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/words_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/words_provider.dart';
import 'package:kute/screens/creation/recover_wallet.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

// Public synthetic vectors. Never fund them.
const _twelve = 'abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon about';
final _twentyFour = [...List.filled(23, 'abandon'), 'art'];

class _Words extends MnemonicWords {
  @override
  Future<List<String>> loadWordList() async =>
      ['abandon', 'ability', 'able', 'about', 'art'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? clipboardText;
  late List<String?> clipboardWrites;
  late int clipboardReads;
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    clipboardText = null;
    clipboardWrites = [];
    clipboardReads = 0;
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.android));
    messenger.setMockMethodCallHandler(
        KeychainLocal.channel, (call) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardReads++;
        return clipboardText == null ? null : {'text': clipboardText};
      }
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
        clipboardWrites.add(clipboardText);
      }
      return null;
    });
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecureScreenController.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wallet = WalletConfig(id: 'existing', name: 'Spending');
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
          wallets: [wallet],
          activeWalletId: wallet.id,
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: true,
          biometricsEnabled: false,
          bitcoinElectrumNode: 'ssl://example.com:50002',
          nodeType: 'electrum',
          reviewDone: true))),
      mnemonicWordsProvider.overrideWithValue(_Words()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const RecoverWallet(),
              )),
    ));
    await tester.pumpAndSettle();
  }

  // The word fields, in grid order (the first TextField is the name).
  List<TextField> wordFields(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .where((f) => f.keyboardType == TextInputType.visiblePassword)
      .toList();

  Future<void> tapPaste(WidgetTester tester) async {
    final paste = find.byKey(const ValueKey('recover-paste'));
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pumpAndSettle();
  }

  testWidgets('Paste fills all 12 fields from a messy paste, then clears it',
      (tester) async {
    await mount(tester);
    clipboardText = _twelve
        .split(' ')
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.toUpperCase()}')
        .join(',\n');

    await tapPaste(tester);

    final fields = wordFields(tester);
    expect(fields, hasLength(12));
    expect(fields.map((f) => f.controller!.text).join(' '), _twelve);
    for (final f in fields) {
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
      expect(f.enableIMEPersonalizedLearning, isFalse);
    }
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    // Cleared because it still held the phrase.
    expect(clipboardWrites, ['']);
    final pasted = events.where((e) => e.$1 == 'recovery_phrase_pasted');
    expect(pasted.single.$2, {'source': 'button', 'result': 'ok'});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a 24-word paste grows the grid to 24 fields', (tester) async {
    await mount(tester);
    clipboardText = _twentyFour.join('  \n ');

    await tapPaste(tester);

    final fields = wordFields(tester);
    expect(fields, hasLength(24));
    expect(fields.map((f) => f.controller!.text).toList(), _twentyFour);
    expect(clipboardWrites, ['']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a word outside the list is marked with the error style',
      (tester) async {
    await mount(tester);
    clipboardText = _twelve.replaceFirst('about', 'abuot');

    await tapPaste(tester);

    expect(wordFields(tester).last.controller!.text, 'abuot');
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('something that is not a phrase leaves grid and clipboard alone',
      (tester) async {
    await mount(tester);
    clipboardText = 'bc1qsomeaddress the user copied';

    await tapPaste(tester);

    expect(wordFields(tester).every((f) => f.controller!.text.isEmpty),
        isTrue);
    expect(clipboardWrites, isEmpty);
    expect(clipboardText, 'bc1qsomeaddress the user copied');
    expect(clipboardReads, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the entry screen shows one instruction line, no word hints',
      (tester) async {
    await mount(tester);
    final context = tester.element(find.byType(RecoverWallet));
    expect(find.text(context.l10n.recoverWithRecoveryPhrase), findsOneWidget);
    // No suggestion strip before anything is typed.
    for (final word in ['abandon', 'ability', 'able', 'about', 'art']) {
      expect(find.text(word), findsNothing);
    }
  });
}
