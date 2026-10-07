import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bg.dart';
import 'app_localizations_cs.dart';
import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_et.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hr.dart';
import 'app_localizations_hu.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_lt.dart';
import 'app_localizations_lv.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ro.dart';
import 'app_localizations_sk.dart';
import 'app_localizations_sl.dart';
import 'app_localizations_sv.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bg'),
    Locale('cs'),
    Locale('da'),
    Locale('de'),
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('et'),
    Locale('fi'),
    Locale('fr'),
    Locale('hr'),
    Locale('hu'),
    Locale('it'),
    Locale('ja'),
    Locale('lt'),
    Locale('lv'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ro'),
    Locale('sk'),
    Locale('sl'),
    Locale('sv')
  ];

  /// No description provided for @totalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total Balance'**
  String get totalBalance;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @recoverAccount.
  ///
  /// In en, this message translates to:
  /// **'Recover Account'**
  String get recoverAccount;

  /// Title of the passkey restore picker when exactly one wallet was found.
  ///
  /// In en, this message translates to:
  /// **'Restore this wallet?'**
  String get recoverPickWalletOne;

  /// Title of the passkey restore picker when several wallets were found.
  ///
  /// In en, this message translates to:
  /// **'Pick a wallet to restore'**
  String get recoverPickWalletMany;

  /// No description provided for @setPin.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get setPin;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @exchange.
  ///
  /// In en, this message translates to:
  /// **'Exchange'**
  String get exchange;

  /// No description provided for @pay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get pay;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @bitcoinUnit.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin unit'**
  String get bitcoinUnit;

  /// No description provided for @deleteWallet.
  ///
  /// In en, this message translates to:
  /// **'Delete Wallet'**
  String get deleteWallet;

  /// No description provided for @receiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get receiving;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sending;

  /// No description provided for @portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get portuguese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @assets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assets;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @swap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swap;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @fastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get fastest;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @flash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get flash;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @fee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get fee;

  /// No description provided for @allTransactions.
  ///
  /// In en, this message translates to:
  /// **'All Transactions'**
  String get allTransactions;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @multiple.
  ///
  /// In en, this message translates to:
  /// **'Multiple'**
  String get multiple;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @pleaseAuthenticateToOpenTheApp.
  ///
  /// In en, this message translates to:
  /// **'Please authenticate to open the app'**
  String get pleaseAuthenticateToOpenTheApp;

  /// No description provided for @invalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get invalidAddress;

  /// No description provided for @transactionSent.
  ///
  /// In en, this message translates to:
  /// **'Transaction Sent'**
  String get transactionSent;

  /// No description provided for @transactionReceived.
  ///
  /// In en, this message translates to:
  /// **'Transaction Received'**
  String get transactionReceived;

  /// No description provided for @unconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed'**
  String get unconfirmed;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @burn.
  ///
  /// In en, this message translates to:
  /// **'Burn'**
  String get burn;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @swaps.
  ///
  /// In en, this message translates to:
  /// **'Swaps'**
  String get swaps;

  /// No description provided for @orderId.
  ///
  /// In en, this message translates to:
  /// **'Order ID'**
  String get orderId;

  /// No description provided for @receivedAt.
  ///
  /// In en, this message translates to:
  /// **'Received at'**
  String get receivedAt;

  /// No description provided for @sendTransaction.
  ///
  /// In en, this message translates to:
  /// **'Send Transaction'**
  String get sendTransaction;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @confirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirmations'**
  String get confirmations;

  /// No description provided for @needed.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get needed;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get days;

  /// No description provided for @weeks.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get weeks;

  /// No description provided for @amountIsTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Amount is too small'**
  String get amountIsTooSmall;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @claimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get claimed;

  /// No description provided for @claim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get claim;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get currentBalance;

  /// No description provided for @addressCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Address copied to clipboard'**
  String get addressCopiedToClipboard;

  /// No description provided for @refund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get refund;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @spending.
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get spending;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @words.
  ///
  /// In en, this message translates to:
  /// **'words'**
  String get words;

  /// No description provided for @word.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get word;

  /// No description provided for @backupWallet.
  ///
  /// In en, this message translates to:
  /// **'Backup Wallet'**
  String get backupWallet;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @incorrectSelectionsPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Incorrect selections. Please try again.'**
  String get incorrectSelectionsPleaseTryAgain;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **' today'**
  String get today;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'change'**
  String get change;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @wallets.
  ///
  /// In en, this message translates to:
  /// **'Wallets'**
  String get wallets;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @networkFee.
  ///
  /// In en, this message translates to:
  /// **'Network Fee'**
  String get networkFee;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @createWallet.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get createWallet;

  /// No description provided for @dashboards.
  ///
  /// In en, this message translates to:
  /// **'Dashboards'**
  String get dashboards;

  /// No description provided for @charts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get charts;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'history'**
  String get history;

  /// No description provided for @transactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get transactionDetails;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @origin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get origin;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @instant.
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get instant;

  /// No description provided for @openSupportChat.
  ///
  /// In en, this message translates to:
  /// **'Open support chat'**
  String get openSupportChat;

  /// No description provided for @paymentId.
  ///
  /// In en, this message translates to:
  /// **'Payment ID'**
  String get paymentId;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome,'**
  String get welcome;

  /// No description provided for @dailyLimit.
  ///
  /// In en, this message translates to:
  /// **'Daily limit'**
  String get dailyLimit;

  /// No description provided for @recover.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recover;

  /// No description provided for @affiliate.
  ///
  /// In en, this message translates to:
  /// **'Affiliate'**
  String get affiliate;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @silver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get silver;

  /// No description provided for @gold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get gold;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'Registered:'**
  String get registered;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @affiliateCode.
  ///
  /// In en, this message translates to:
  /// **'Affiliate Code'**
  String get affiliateCode;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @insufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'Insufficient funds'**
  String get insufficientFunds;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @amounts.
  ///
  /// In en, this message translates to:
  /// **'Amounts'**
  String get amounts;

  /// No description provided for @fees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get fees;

  /// No description provided for @awaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get awaitingPayment;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About '**
  String get about;

  /// No description provided for @paymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get paymentReceived;

  /// No description provided for @totalFees.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get totalFees;

  /// No description provided for @confirmPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPin;

  /// No description provided for @pinsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get pinsDoNotMatch;

  /// No description provided for @attemptsRemaining.
  ///
  /// In en, this message translates to:
  /// **'attempts remaining'**
  String get attemptsRemaining;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price: '**
  String get price;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin'**
  String get bitcoin;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'payments'**
  String get payments;

  /// No description provided for @migrate.
  ///
  /// In en, this message translates to:
  /// **'Migrate'**
  String get migrate;

  /// No description provided for @invalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid Input'**
  String get invalidInput;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @information.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get information;

  /// No description provided for @fromAsset.
  ///
  /// In en, this message translates to:
  /// **'From Asset'**
  String get fromAsset;

  /// No description provided for @toAsset.
  ///
  /// In en, this message translates to:
  /// **'To Asset'**
  String get toAsset;

  /// No description provided for @providerFee.
  ///
  /// In en, this message translates to:
  /// **'Provider fee'**
  String get providerFee;

  /// No description provided for @networkFee2.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get networkFee2;

  /// No description provided for @minAmount.
  ///
  /// In en, this message translates to:
  /// **'Min amount'**
  String get minAmount;

  /// No description provided for @price2.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price2;

  /// No description provided for @feeRate.
  ///
  /// In en, this message translates to:
  /// **'Fee rate'**
  String get feeRate;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @buy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get buy;

  /// No description provided for @sell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sell;

  /// No description provided for @deposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get deposit;

  /// No description provided for @serviceFee.
  ///
  /// In en, this message translates to:
  /// **'Service Fee'**
  String get serviceFee;

  /// No description provided for @store.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get store;

  /// No description provided for @paymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment Status'**
  String get paymentStatus;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @asset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get asset;

  /// No description provided for @recipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get recipient;

  /// No description provided for @confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// No description provided for @transactionId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get transactionId;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @blocks.
  ///
  /// In en, this message translates to:
  /// **'blocks'**
  String get blocks;

  /// No description provided for @purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchase;

  /// The door that funds the bitcoin balance, always shown beside the bitcoin mark. Mirrors dollarDeposit on the Dollars screen.
  ///
  /// In en, this message translates to:
  /// **'Purchase Bitcoin'**
  String get purchaseBitcoin;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @searchAction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchAction;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get all;

  /// No description provided for @confirmTransaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm Transaction'**
  String get confirmTransaction;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncing;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactions;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'(Optional)'**
  String get optional;

  /// No description provided for @recipientAddress.
  ///
  /// In en, this message translates to:
  /// **'Recipient Address'**
  String get recipientAddress;

  /// No description provided for @variation.
  ///
  /// In en, this message translates to:
  /// **'Variation'**
  String get variation;

  /// No description provided for @chatWithSupport.
  ///
  /// In en, this message translates to:
  /// **'Chat with support'**
  String get chatWithSupport;

  /// No description provided for @id.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get id;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get min;

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get max;

  /// Screen-reader label of the Max chip beside an amount: fills the largest amount allowed.
  ///
  /// In en, this message translates to:
  /// **'Use maximum'**
  String get amountUseMaximum;

  /// No description provided for @serviceFee2.
  ///
  /// In en, this message translates to:
  /// **'Service fee'**
  String get serviceFee2;

  /// No description provided for @backupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Backup Completed'**
  String get backupCompleted;

  /// No description provided for @waitingForDeposit.
  ///
  /// In en, this message translates to:
  /// **'Waiting for deposit'**
  String get waitingForDeposit;

  /// No description provided for @refundInProgress.
  ///
  /// In en, this message translates to:
  /// **'Refund in progress'**
  String get refundInProgress;

  /// No description provided for @shift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get shift;

  /// No description provided for @expiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires At'**
  String get expiresAt;

  /// No description provided for @coin.
  ///
  /// In en, this message translates to:
  /// **'Coin'**
  String get coin;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @memo.
  ///
  /// In en, this message translates to:
  /// **'Memo'**
  String get memo;

  /// No description provided for @networkFeeUsd.
  ///
  /// In en, this message translates to:
  /// **'Network Fee USD'**
  String get networkFeeUsd;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @receiveAddress.
  ///
  /// In en, this message translates to:
  /// **'Receive Address'**
  String get receiveAddress;

  /// No description provided for @mandatory.
  ///
  /// In en, this message translates to:
  /// **'(Mandatory)'**
  String get mandatory;

  /// No description provided for @refreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing'**
  String get refreshing;

  /// No description provided for @release.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get release;

  /// No description provided for @insufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get insufficientBalance;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @forgotPin2.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get forgotPin2;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricUnlock;

  /// No description provided for @createAPin.
  ///
  /// In en, this message translates to:
  /// **'Create a PIN'**
  String get createAPin;

  /// No description provided for @confirmYourPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm Your PIN'**
  String get confirmYourPin;

  /// No description provided for @depositAddress.
  ///
  /// In en, this message translates to:
  /// **'Deposit address'**
  String get depositAddress;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @marketData.
  ///
  /// In en, this message translates to:
  /// **'Market Data'**
  String get marketData;

  /// No description provided for @swapInitiated.
  ///
  /// In en, this message translates to:
  /// **'Swap Initiated'**
  String get swapInitiated;

  /// No description provided for @reverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get reverse;

  /// No description provided for @refunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get refunded;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @pleaseEnterAValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get pleaseEnterAValidAmount;

  /// No description provided for @usernameUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Username updated successfully!'**
  String get usernameUpdatedSuccessfully;

  /// No description provided for @editUsername.
  ///
  /// In en, this message translates to:
  /// **'Edit Username'**
  String get editUsername;

  /// No description provided for @editLightningAddress.
  ///
  /// In en, this message translates to:
  /// **'Edit Lightning Address'**
  String get editLightningAddress;

  /// No description provided for @pleaseEnterAUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username.'**
  String get pleaseEnterAUsername;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @usernameAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Username already exists'**
  String get usernameAlreadyExists;

  /// No description provided for @anErrorOccurredPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again.'**
  String get anErrorOccurredPleaseTryAgain;

  /// No description provided for @paymentPending.
  ///
  /// In en, this message translates to:
  /// **'Payment Pending'**
  String get paymentPending;

  /// No description provided for @expires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expires;

  /// No description provided for @enterRefundAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter refund address'**
  String get enterRefundAddress;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @onChainTxid.
  ///
  /// In en, this message translates to:
  /// **'On-chain TXID'**
  String get onChainTxid;

  /// No description provided for @paymentHash.
  ///
  /// In en, this message translates to:
  /// **'Payment Hash'**
  String get paymentHash;

  /// No description provided for @sendTx.
  ///
  /// In en, this message translates to:
  /// **'Send TX'**
  String get sendTx;

  /// No description provided for @verifyBackup.
  ///
  /// In en, this message translates to:
  /// **'Verify Backup'**
  String get verifyBackup;

  /// No description provided for @slow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get slow;

  /// No description provided for @fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get fast;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @transactionIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID copied'**
  String get transactionIdCopied;

  /// No description provided for @quoting.
  ///
  /// In en, this message translates to:
  /// **'Quoting'**
  String get quoting;

  /// No description provided for @valuation.
  ///
  /// In en, this message translates to:
  /// **'Valuation'**
  String get valuation;

  /// No description provided for @allocation.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get allocation;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get checking;

  /// No description provided for @comingSoon2.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon2;

  /// No description provided for @sendTo.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get sendTo;

  /// No description provided for @quoteExpired.
  ///
  /// In en, this message translates to:
  /// **'Quote expired'**
  String get quoteExpired;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @actionRequired.
  ///
  /// In en, this message translates to:
  /// **'Action Required'**
  String get actionRequired;

  /// No description provided for @activeWallet.
  ///
  /// In en, this message translates to:
  /// **'Active wallet'**
  String get activeWallet;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @addressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get addressCopied;

  /// No description provided for @addressMismatchTheAddressOnYourJadeDoesNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Address mismatch! The address on your Jade does not match.'**
  String get addressMismatchTheAddressOnYourJadeDoesNotMatch;

  /// No description provided for @addressMismatchTheAddressOnYourLedgerDoesNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Address mismatch! The address on your Ledger does not match.'**
  String get addressMismatchTheAddressOnYourLedgerDoesNotMatch;

  /// No description provided for @addressVerifiedOnJade.
  ///
  /// In en, this message translates to:
  /// **'Address verified on Jade'**
  String get addressVerifiedOnJade;

  /// No description provided for @addressVerifiedOnLedger.
  ///
  /// In en, this message translates to:
  /// **'Address verified on Ledger'**
  String get addressVerifiedOnLedger;

  /// No description provided for @afterYourDeviceSignsTheTransactionScanTheSignedQrCodeItDisplays.
  ///
  /// In en, this message translates to:
  /// **'After your device signs the transaction, scan the signed QR code it displays.'**
  String get afterYourDeviceSignsTheTransactionScanTheSignedQrCodeItDisplays;

  /// No description provided for @appPin.
  ///
  /// In en, this message translates to:
  /// **'App PIN'**
  String get appPin;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @avg.
  ///
  /// In en, this message translates to:
  /// **'Avg'**
  String get avg;

  /// No description provided for @btc.
  ///
  /// In en, this message translates to:
  /// **'BTC'**
  String get btc;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @bitcoinAddress.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Address'**
  String get bitcoinAddress;

  /// No description provided for @bitcoinNetwork.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Network'**
  String get bitcoinNetwork;

  /// No description provided for @bitcoinLightningSpark.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin, Lightning & Spark'**
  String get bitcoinLightningSpark;

  /// No description provided for @blockHeight.
  ///
  /// In en, this message translates to:
  /// **'Block Height'**
  String get blockHeight;

  /// No description provided for @buys.
  ///
  /// In en, this message translates to:
  /// **'Buys'**
  String get buys;

  /// No description provided for @changeUnlockCode.
  ///
  /// In en, this message translates to:
  /// **'Change unlock code'**
  String get changeUnlockCode;

  /// No description provided for @chooseWhichWalletsToIncludeInTheReport.
  ///
  /// In en, this message translates to:
  /// **'Choose which wallets to include in the report.'**
  String get chooseWhichWalletsToIncludeInTheReport;

  /// No description provided for @claimDeposit.
  ///
  /// In en, this message translates to:
  /// **'Claim Deposit'**
  String get claimDeposit;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @confirmClaim.
  ///
  /// In en, this message translates to:
  /// **'Confirm Claim'**
  String get confirmClaim;

  /// No description provided for @confirmRefund.
  ///
  /// In en, this message translates to:
  /// **'Confirm Refund'**
  String get confirmRefund;

  /// No description provided for @connectSign.
  ///
  /// In en, this message translates to:
  /// **'Connect & Sign'**
  String get connectSign;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get createdAt;

  /// No description provided for @creatingWallet.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet...'**
  String get creatingWallet;

  /// No description provided for @currentWallet.
  ///
  /// In en, this message translates to:
  /// **'Current Wallet'**
  String get currentWallet;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @destinationNetwork.
  ///
  /// In en, this message translates to:
  /// **'Destination Network'**
  String get destinationNetwork;

  /// No description provided for @displayCurrency.
  ///
  /// In en, this message translates to:
  /// **'Display currency'**
  String get displayCurrency;

  /// No description provided for @electrumNode.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin server'**
  String get electrumNode;

  /// No description provided for @encrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get encrypted;

  /// No description provided for @ensureTheNodeIsActiveIncorrectNodesMayShowIncorrectBalances.
  ///
  /// In en, this message translates to:
  /// **'Ensure the node is active. Incorrect nodes may show incorrect balances.'**
  String get ensureTheNodeIsActiveIncorrectNodesMayShowIncorrectBalances;

  /// No description provided for @enterAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get enterAmount;

  /// No description provided for @enterAAssetCodeAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a {assetCode} address'**
  String enterAAssetCodeAddress(String assetCode);

  /// No description provided for @enterTheBitcoinAddressAndFeeRateToRefund.
  ///
  /// In en, this message translates to:
  /// **'Enter the Bitcoin address and fee rate to refund.'**
  String get enterTheBitcoinAddressAndFeeRateToRefund;

  /// No description provided for @enterYourPinOnTheJadeDevice.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN on the Jade device...'**
  String get enterYourPinOnTheJadeDevice;

  /// No description provided for @errorLoadingUtxos.
  ///
  /// In en, this message translates to:
  /// **'Could not load coins'**
  String get errorLoadingUtxos;

  /// No description provided for @errorLoadingData.
  ///
  /// In en, this message translates to:
  /// **'Error loading data'**
  String get errorLoadingData;

  /// No description provided for @errorLoadingPriceData.
  ///
  /// In en, this message translates to:
  /// **'Error loading price data'**
  String get errorLoadingPriceData;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get exportPeriod;

  /// No description provided for @exportPeriodAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get exportPeriodAllTime;

  /// No description provided for @exportPeriodThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get exportPeriodThisYear;

  /// No description provided for @exportPeriodLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get exportPeriodLastYear;

  /// No description provided for @exportPeriodLast90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get exportPeriodLast90Days;

  /// No description provided for @exportOrientationOnly.
  ///
  /// In en, this message translates to:
  /// **'This report is for personal orientation only. It is not a tax document and may be incomplete or inaccurate.'**
  String get exportOrientationOnly;

  /// No description provided for @exportActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'PDF report or CSV spreadsheet of your wallet, investing and predictions activity'**
  String get exportActivitySubtitle;

  /// No description provided for @exportTransactionsSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Export transactions'**
  String get exportTransactionsSheetTitle;

  /// No description provided for @exported.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exported;

  /// No description provided for @failedToGetAddress.
  ///
  /// In en, this message translates to:
  /// **'Failed to get Address'**
  String get failedToGetAddress;

  /// No description provided for @failedToLoadUtxos.
  ///
  /// In en, this message translates to:
  /// **'Could not load coins'**
  String get failedToLoadUtxos;

  /// No description provided for @fasterIsMoreExpensiveSlowerIsCheaperButTakesLonger.
  ///
  /// In en, this message translates to:
  /// **'Faster is more expensive, slower is cheaper but takes longer.'**
  String get fasterIsMoreExpensiveSlowerIsCheaperButTakesLonger;

  /// No description provided for @feeRate2.
  ///
  /// In en, this message translates to:
  /// **'Fee Rate'**
  String get feeRate2;

  /// No description provided for @hlMarketInvestCta.
  ///
  /// In en, this message translates to:
  /// **'Invest'**
  String get hlMarketInvestCta;

  /// No description provided for @feeRateSatsVbyte.
  ///
  /// In en, this message translates to:
  /// **'Fee Rate (sats/vByte)'**
  String get feeRateSatsVbyte;

  /// No description provided for @financials.
  ///
  /// In en, this message translates to:
  /// **'Financials'**
  String get financials;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// First half of the welcome screen headline. The accent lands on the second half, so the two are separate strings and the lead keeps its trailing space.
  ///
  /// In en, this message translates to:
  /// **'Change starts with '**
  String get startTaglineLead;

  /// Second half of the welcome screen headline, drawn in the accent colour.
  ///
  /// In en, this message translates to:
  /// **'you.'**
  String get startTaglineAccent;

  /// No description provided for @iAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get iAlreadyHaveAnAccount;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @howItWorks2.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get howItWorks2;

  /// No description provided for @importSignedFile.
  ///
  /// In en, this message translates to:
  /// **'Import Signed File'**
  String get importSignedFile;

  /// No description provided for @importTheSignedFileBackFromYourSdCard.
  ///
  /// In en, this message translates to:
  /// **'Import the signed file back from your SD card.'**
  String get importTheSignedFileBackFromYourSdCard;

  /// No description provided for @incorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get incorrectPin;

  /// No description provided for @inputsOutputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs / Outputs'**
  String get inputsOutputs;

  /// No description provided for @insufficientBalanceForFees.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance for fees'**
  String get insufficientBalanceForFees;

  /// No description provided for @invalidAddressOrAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid address or amount'**
  String get invalidAddressOrAmount;

  /// No description provided for @invalidRate.
  ///
  /// In en, this message translates to:
  /// **'Invalid rate'**
  String get invalidRate;

  /// No description provided for @liquidity.
  ///
  /// In en, this message translates to:
  /// **'LIQUIDITY'**
  String get liquidity;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last Updated'**
  String get lastUpdated;

  /// No description provided for @lastAttemptWalletWillBeErased.
  ///
  /// In en, this message translates to:
  /// **'Last attempt. Wallet will be erased.'**
  String get lastAttemptWalletWillBeErased;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @lightningBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Lightning Bitcoin'**
  String get lightningBitcoin;

  /// No description provided for @loadTheFileOnYourSigningDeviceAndApproveTheTransaction.
  ///
  /// In en, this message translates to:
  /// **'Load the file on your signing device and approve the transaction.'**
  String get loadTheFileOnYourSigningDeviceAndApproveTheTransaction;

  /// No description provided for @mustBe6Digits.
  ///
  /// In en, this message translates to:
  /// **'Must be 6 digits'**
  String get mustBe6Digits;

  /// No description provided for @netFlow.
  ///
  /// In en, this message translates to:
  /// **'Net Flow'**
  String get netFlow;

  /// No description provided for @networkSpeed.
  ///
  /// In en, this message translates to:
  /// **'Network Speed'**
  String get networkSpeed;

  /// No description provided for @feeEstimateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Fee estimate unavailable. Retry or set a custom fee.'**
  String get feeEstimateUnavailable;

  /// No description provided for @feeRatesStale.
  ///
  /// In en, this message translates to:
  /// **'Live fee rates are unavailable right now. These are recent estimates.'**
  String get feeRatesStale;

  /// No description provided for @feeSpeedTimeRate.
  ///
  /// In en, this message translates to:
  /// **'{time}  ·  {rate} sat/vB'**
  String feeSpeedTimeRate(String time, String rate);

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @customFeeActive.
  ///
  /// In en, this message translates to:
  /// **'Custom fee: {rate} sat/vB'**
  String customFeeActive(String rate);

  /// No description provided for @coinSelectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 coin selected} other{{count} coins selected}}'**
  String coinSelectionCount(int count);

  /// No description provided for @coinSelectionToSend.
  ///
  /// In en, this message translates to:
  /// **'To send'**
  String get coinSelectionToSend;

  /// No description provided for @coinSelectionEstimatedFee.
  ///
  /// In en, this message translates to:
  /// **'Estimated fee'**
  String get coinSelectionEstimatedFee;

  /// No description provided for @coinSelectionEnough.
  ///
  /// In en, this message translates to:
  /// **'Enough to cover the payment and the network fee.'**
  String get coinSelectionEnough;

  /// No description provided for @coinSelectionNotEnough.
  ///
  /// In en, this message translates to:
  /// **'Not enough yet. Select more coins.'**
  String get coinSelectionNotEnough;

  /// No description provided for @coinSelectionAutomaticHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic selection picks the coins for you.'**
  String get coinSelectionAutomaticHint;

  /// No description provided for @coinSelectionDrainHint.
  ///
  /// In en, this message translates to:
  /// **'Every selected coin will be sent in full.'**
  String get coinSelectionDrainHint;

  /// No description provided for @noUtxosAvailable.
  ///
  /// In en, this message translates to:
  /// **'No coins available'**
  String get noUtxosAvailable;

  /// No description provided for @noActiveWalletFound.
  ///
  /// In en, this message translates to:
  /// **'No active wallet found.'**
  String get noActiveWalletFound;

  /// No description provided for @noPriceDataForThisRange.
  ///
  /// In en, this message translates to:
  /// **'No price data for this range'**
  String get noPriceDataForThisRange;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @noTransactionSelected.
  ///
  /// In en, this message translates to:
  /// **'No transaction selected'**
  String get noTransactionSelected;

  /// No description provided for @noTransactionsToExport.
  ///
  /// In en, this message translates to:
  /// **'No transactions to export'**
  String get noTransactionsToExport;

  /// No description provided for @noWalletSelected.
  ///
  /// In en, this message translates to:
  /// **'No wallet selected'**
  String get noWalletSelected;

  /// No description provided for @nodeId.
  ///
  /// In en, this message translates to:
  /// **'Node ID'**
  String get nodeId;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not Available'**
  String get notAvailable;

  /// No description provided for @onlyLowercaseLettersNumbersAndAreAllowed2.
  ///
  /// In en, this message translates to:
  /// **'Only lowercase letters, numbers, and \"._-\" are allowed.'**
  String get onlyLowercaseLettersNumbersAndAreAllowed2;

  /// No description provided for @out.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get out;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @pasteSignedTransactionHere.
  ///
  /// In en, this message translates to:
  /// **'Paste signed transaction here...'**
  String get pasteSignedTransactionHere;

  /// No description provided for @pasteTheSignedTransactionBelowAndSubmit.
  ///
  /// In en, this message translates to:
  /// **'Paste the signed transaction below and submit.'**
  String get pasteTheSignedTransactionBelowAndSubmit;

  /// No description provided for @pleaseEnterAWalletName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a wallet name'**
  String get pleaseEnterAWalletName;

  /// No description provided for @pleaseEnterAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter an address.'**
  String get pleaseEnterAnAddress;

  /// No description provided for @pleaseSetUpYourPinFirst.
  ///
  /// In en, this message translates to:
  /// **'Please set up your PIN first'**
  String get pleaseSetUpYourPinFirst;

  /// No description provided for @popular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get popular;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @preimage.
  ///
  /// In en, this message translates to:
  /// **'Preimage'**
  String get preimage;

  /// No description provided for @private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get private;

  /// No description provided for @receiveBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Receive Bitcoin'**
  String get receiveBitcoin;

  /// No description provided for @refundDeposit.
  ///
  /// In en, this message translates to:
  /// **'Refund Deposit'**
  String get refundDeposit;

  /// No description provided for @refunding.
  ///
  /// In en, this message translates to:
  /// **'Refunding'**
  String get refunding;

  /// No description provided for @refundingDeposit.
  ///
  /// In en, this message translates to:
  /// **'Refunding Deposit'**
  String get refundingDeposit;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameWallet.
  ///
  /// In en, this message translates to:
  /// **'Rename Wallet'**
  String get renameWallet;

  /// No description provided for @requirements.
  ///
  /// In en, this message translates to:
  /// **'Requirements:'**
  String get requirements;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @scanSignedQr.
  ///
  /// In en, this message translates to:
  /// **'Scan Signed QR'**
  String get scanSignedQr;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @selectADateRange.
  ///
  /// In en, this message translates to:
  /// **'Select a date range.'**
  String get selectADateRange;

  /// No description provided for @selectTheCorrectWordForEachPosition2.
  ///
  /// In en, this message translates to:
  /// **'Select the correct word for each position'**
  String get selectTheCorrectWordForEachPosition2;

  /// No description provided for @sells.
  ///
  /// In en, this message translates to:
  /// **'Sells'**
  String get sells;

  /// No description provided for @signedTransactionDoesNotMatchOriginalBroadcastAborted.
  ///
  /// In en, this message translates to:
  /// **'Signed transaction does not match the original. Broadcast aborted for safety.'**
  String get signedTransactionDoesNotMatchOriginalBroadcastAborted;

  /// No description provided for @showThisQrCodeToYourSigningDeviceAndLetItScanAllFrames.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code to your signing device and let it scan all frames.'**
  String get showThisQrCodeToYourSigningDeviceAndLetItScanAllFrames;

  /// No description provided for @signTheTransactionWithYourExternalToolOrDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign the transaction with your external tool or device.'**
  String get signTheTransactionWithYourExternalToolOrDevice;

  /// No description provided for @sparkTransfer.
  ///
  /// In en, this message translates to:
  /// **'Spark Transfer'**
  String get sparkTransfer;

  /// No description provided for @split.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get split;

  /// No description provided for @tapBelowToConnectYouLlBePromptedToOpenTheBitcoinAppIfNeeded.
  ///
  /// In en, this message translates to:
  /// **'Tap below to connect. You\'ll be prompted to open the Bitcoin app if needed.'**
  String get tapBelowToConnectYouLlBePromptedToOpenTheBitcoinAppIfNeeded;

  /// No description provided for @technicalDetails.
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get technicalDetails;

  /// No description provided for @timestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get timestamp;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @totalFee.
  ///
  /// In en, this message translates to:
  /// **'Total Fee'**
  String get totalFee;

  /// No description provided for @usdEarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Earn'**
  String get usdEarnTitle;

  /// No description provided for @usdEarnRate.
  ///
  /// In en, this message translates to:
  /// **'Recent yearly rate'**
  String get usdEarnRate;

  /// Label above the amount the rewards programme pays at the next daily cut.
  ///
  /// In en, this message translates to:
  /// **'Next payment'**
  String get usdEarnNextPayment;

  /// Label above the countdown to the next payout, which is cut at 00:00 UTC.
  ///
  /// In en, this message translates to:
  /// **'Pays in'**
  String get usdEarnNextPaymentIn;

  /// No description provided for @usdEarnRatePending.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get usdEarnRatePending;

  /// No description provided for @usdEarnRateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable right now'**
  String get usdEarnRateUnavailable;

  /// No description provided for @usdEarnPaidToDate.
  ///
  /// In en, this message translates to:
  /// **'Paid to you so far'**
  String get usdEarnPaidToDate;

  /// No description provided for @usdEarnActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get usdEarnActivityEmpty;

  /// No description provided for @usdEarnActivityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Payment history is unavailable right now'**
  String get usdEarnActivityUnavailable;

  /// No description provided for @hlYieldAvailableLine.
  ///
  /// In en, this message translates to:
  /// **'{amount} available'**
  String hlYieldAvailableLine(String amount);

  /// No description provided for @trackAddress.
  ///
  /// In en, this message translates to:
  /// **'Track Address'**
  String get trackAddress;

  /// No description provided for @trading.
  ///
  /// In en, this message translates to:
  /// **'Investing'**
  String get trading;

  /// No description provided for @turnOnYourJadeAndEnableBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Turn on your Jade and enable Bluetooth.'**
  String get turnOnYourJadeAndEnableBluetooth;

  /// No description provided for @txId.
  ///
  /// In en, this message translates to:
  /// **'Tx ID'**
  String get txId;

  /// No description provided for @unclaimedDeposit.
  ///
  /// In en, this message translates to:
  /// **'Unclaimed Deposit'**
  String get unclaimedDeposit;

  /// No description provided for @verifyYourBackup.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Backup'**
  String get verifyYourBackup;

  /// No description provided for @verifyOnJade.
  ///
  /// In en, this message translates to:
  /// **'Verify on Jade'**
  String get verifyOnJade;

  /// No description provided for @verifyOnLedger.
  ///
  /// In en, this message translates to:
  /// **'Verify on Ledger'**
  String get verifyOnLedger;

  /// No description provided for @verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get verifying;

  /// No description provided for @viewInMempool.
  ///
  /// In en, this message translates to:
  /// **'View in Mempool'**
  String get viewInMempool;

  /// No description provided for @viewOnSparkScan.
  ///
  /// In en, this message translates to:
  /// **'View on Spark Scan'**
  String get viewOnSparkScan;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @vout.
  ///
  /// In en, this message translates to:
  /// **'Vout'**
  String get vout;

  /// No description provided for @walletCreated.
  ///
  /// In en, this message translates to:
  /// **'Wallet Created'**
  String get walletCreated;

  /// No description provided for @walletName.
  ///
  /// In en, this message translates to:
  /// **'Wallet Name'**
  String get walletName;

  /// No description provided for @watchOnly.
  ///
  /// In en, this message translates to:
  /// **'Watch Only'**
  String get watchOnly;

  /// No description provided for @withdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdraw;

  /// No description provided for @youReceive.
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get youReceive;

  /// No description provided for @youSend.
  ///
  /// In en, this message translates to:
  /// **'You send'**
  String get youSend;

  /// No description provided for @k10Min.
  ///
  /// In en, this message translates to:
  /// **'~10 min'**
  String get k10Min;

  /// No description provided for @k30Min.
  ///
  /// In en, this message translates to:
  /// **'~30 min'**
  String get k30Min;

  /// No description provided for @k60Min.
  ///
  /// In en, this message translates to:
  /// **'~60 min'**
  String get k60Min;

  /// No description provided for @predictions.
  ///
  /// In en, this message translates to:
  /// **'Predictions'**
  String get predictions;

  /// No description provided for @enterPinToContinue.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN to continue'**
  String get enterPinToContinue;

  /// No description provided for @verifyYourIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity'**
  String get verifyYourIdentity;

  /// No description provided for @restoreSecretsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore your wallets on this phone'**
  String get restoreSecretsTitle;

  /// No description provided for @restoreSecretsBody.
  ///
  /// In en, this message translates to:
  /// **'Your wallet key stays on your old phone for your safety, so it did not move with your data. Restore each wallet to keep going here.'**
  String get restoreSecretsBody;

  /// No description provided for @restoreNeedsRecovery.
  ///
  /// In en, this message translates to:
  /// **'Needs recovery'**
  String get restoreNeedsRecovery;

  /// No description provided for @restoreWalletRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restoreWalletRestored;

  /// No description provided for @restoreEnterPhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery phrase'**
  String get restoreEnterPhrase;

  /// No description provided for @restorePhraseMatch.
  ///
  /// In en, this message translates to:
  /// **'These words match {walletName}.'**
  String restorePhraseMatch(String walletName);

  /// No description provided for @restorePhraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'These words belong to a different wallet. Check them and try again.'**
  String get restorePhraseMismatch;

  /// No description provided for @restorePhraseUnverified.
  ///
  /// In en, this message translates to:
  /// **'{walletName} has no saved check. These words hold {amount} on the Bitcoin network. Use them for this wallet?'**
  String restorePhraseUnverified(String walletName, String amount);

  /// No description provided for @restoreBalanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'an unknown amount'**
  String get restoreBalanceUnknown;

  /// No description provided for @restoreAddAsNewWallet.
  ///
  /// In en, this message translates to:
  /// **'Add as a new wallet'**
  String get restoreAddAsNewWallet;

  /// No description provided for @restoreUseLegacyCopy.
  ///
  /// In en, this message translates to:
  /// **'Use saved recovery copy'**
  String get restoreUseLegacyCopy;

  /// Button that restores a wallet with the passkey held by the platform account. Names the account because that is where the person has to still have access.
  ///
  /// In en, this message translates to:
  /// **'Use your {account}'**
  String restoreUsePasskey(String account);

  /// Shown when a passkey restore fails. Names the platform account so the person knows which one to check.
  ///
  /// In en, this message translates to:
  /// **'Kute couldn\'t restore this wallet with your {account}. Try again.'**
  String restorePasskeyFailed(String account);

  /// No description provided for @restoreUsePhraseInstead.
  ///
  /// In en, this message translates to:
  /// **'Use your 12 words instead'**
  String get restoreUsePhraseInstead;

  /// No description provided for @restoreStartFresh.
  ///
  /// In en, this message translates to:
  /// **'Start fresh'**
  String get restoreStartFresh;

  /// No description provided for @restoreStartFreshConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to remove every wallet from this phone.'**
  String restoreStartFreshConfirm(String word);

  /// No description provided for @restoreStartFreshWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get restoreStartFreshWord;

  /// No description provided for @restoreWalletsAction.
  ///
  /// In en, this message translates to:
  /// **'Restore wallets'**
  String get restoreWalletsAction;

  /// No description provided for @seedUnavailableBanner.
  ///
  /// In en, this message translates to:
  /// **'This wallet needs to be restored on this phone.'**
  String get seedUnavailableBanner;

  /// No description provided for @seedUnavailableAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get seedUnavailableAction;

  /// No description provided for @storageUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Kute can\'t reach your phone\'s secure storage right now.'**
  String get storageUnavailableTitle;

  /// No description provided for @storageUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Your wallets are safe. Try again in a moment.'**
  String get storageUnavailableBody;

  /// No description provided for @storageUnavailableRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get storageUnavailableRetry;

  /// No description provided for @pinSheetLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong PINs. Kute is locked for now.'**
  String get pinSheetLocked;

  /// No description provided for @changePinBlocked.
  ///
  /// In en, this message translates to:
  /// **'Kute can\'t change your PIN while a wallet can\'t be read. Try again later.'**
  String get changePinBlocked;

  /// No description provided for @backupDoneDeviceBound.
  ///
  /// In en, this message translates to:
  /// **'Your 12 words are how you restore this wallet on a new phone. Phone backups and transfers don\'t carry your wallet key.'**
  String get backupDoneDeviceBound;

  /// No description provided for @walletsShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get walletsShowQr;

  /// No description provided for @seedHiddenWhileRecording.
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase is hidden while your screen is being recorded.'**
  String get seedHiddenWhileRecording;

  /// No description provided for @seedScreenshotWarning.
  ///
  /// In en, this message translates to:
  /// **'You took a screenshot of your recovery phrase. Delete it from your photos to keep your wallet safe.'**
  String get seedScreenshotWarning;

  /// No description provided for @lockedForTime.
  ///
  /// In en, this message translates to:
  /// **'Locked for {time}'**
  String lockedForTime(String time);

  /// No description provided for @customFee.
  ///
  /// In en, this message translates to:
  /// **'Custom Fee'**
  String get customFee;

  /// No description provided for @setLabel.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get setLabel;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @sendRouteDetails.
  ///
  /// In en, this message translates to:
  /// **'Route details'**
  String get sendRouteDetails;

  /// No description provided for @sendRouteDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who moves the money and where it goes'**
  String get sendRouteDetailsSubtitle;

  /// No description provided for @sendAssetOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'{asset} on {network}'**
  String sendAssetOnNetwork(String asset, String network);

  /// No description provided for @sendWhichNetworkIsThisAddressOn.
  ///
  /// In en, this message translates to:
  /// **'Which network is this address on?'**
  String get sendWhichNetworkIsThisAddressOn;

  /// No description provided for @sendTapToChoose.
  ///
  /// In en, this message translates to:
  /// **'Tap to choose'**
  String get sendTapToChoose;

  /// No description provided for @sendThisWalletCanOnlySendBitcoin.
  ///
  /// In en, this message translates to:
  /// **'This wallet can only send Bitcoin.'**
  String get sendThisWalletCanOnlySendBitcoin;

  /// No description provided for @sendWhereTo.
  ///
  /// In en, this message translates to:
  /// **'Where to?'**
  String get sendWhereTo;

  /// No description provided for @sendNetworkFeeFor.
  ///
  /// In en, this message translates to:
  /// **'{speed} network fee'**
  String sendNetworkFeeFor(String speed);

  /// No description provided for @scanOnlyFromSpendingWallet.
  ///
  /// In en, this message translates to:
  /// **'This code can only be paid from your spending wallet.'**
  String get scanOnlyFromSpendingWallet;

  /// No description provided for @scanAddressOnAnotherNetwork.
  ///
  /// In en, this message translates to:
  /// **'This address is on another network. Choose which one next.'**
  String get scanAddressOnAnotherNetwork;

  /// No description provided for @hwUnsignedTransactionCopied.
  ///
  /// In en, this message translates to:
  /// **'Unsigned transaction copied'**
  String get hwUnsignedTransactionCopied;

  /// No description provided for @hwApproveOnLedger.
  ///
  /// In en, this message translates to:
  /// **'Approve on your Ledger'**
  String get hwApproveOnLedger;

  /// No description provided for @hwApproveOnJade.
  ///
  /// In en, this message translates to:
  /// **'Approve on your Jade'**
  String get hwApproveOnJade;

  /// No description provided for @hwOtherWaysToSign.
  ///
  /// In en, this message translates to:
  /// **'Other ways to sign'**
  String get hwOtherWaysToSign;

  /// No description provided for @hwExportUnsignedTransactionStep.
  ///
  /// In en, this message translates to:
  /// **'Save the unsigned transaction file to your SD card or device storage.'**
  String get hwExportUnsignedTransactionStep;

  /// No description provided for @hwSaveUnsignedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Save unsigned transaction'**
  String get hwSaveUnsignedTransaction;

  /// No description provided for @hwCopyUnsignedTransactionStep.
  ///
  /// In en, this message translates to:
  /// **'Copy the unsigned transaction and paste it into your signing tool.'**
  String get hwCopyUnsignedTransactionStep;

  /// No description provided for @hwCopyUnsignedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Copy unsigned transaction'**
  String get hwCopyUnsignedTransaction;

  /// No description provided for @hwNerdFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get hwNerdFormat;

  /// No description provided for @hwNerdSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get hwNerdSize;

  /// No description provided for @hwNerdBytes.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String hwNerdBytes(String count);

  /// No description provided for @hwNerdFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Wallet fingerprint'**
  String get hwNerdFingerprint;

  /// No description provided for @hwNerdUnsignedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Unsigned transaction'**
  String get hwNerdUnsignedTransaction;

  /// No description provided for @qrHavingTroubleScanning.
  ///
  /// In en, this message translates to:
  /// **'Having trouble scanning?'**
  String get qrHavingTroubleScanning;

  /// No description provided for @qrCouldNotBuild.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build the QR code for this transaction.'**
  String get qrCouldNotBuild;

  /// No description provided for @qrTooLargeSwitchAnimated.
  ///
  /// In en, this message translates to:
  /// **'This transaction is too large for a single QR code. Switch to Animated and your signing device scans all {count} frames on its own.'**
  String qrTooLargeSwitchAnimated(String count);

  /// No description provided for @qrTooLargeUseAnimated.
  ///
  /// In en, this message translates to:
  /// **'This transaction is too large for a single QR code. Use Animated instead.'**
  String get qrTooLargeUseAnimated;

  /// No description provided for @sendApproveOnYourDeviceNext.
  ///
  /// In en, this message translates to:
  /// **'You approve it on your device next'**
  String get sendApproveOnYourDeviceNext;

  /// No description provided for @sendPreparingTransaction.
  ///
  /// In en, this message translates to:
  /// **'Preparing the transaction…'**
  String get sendPreparingTransaction;

  /// No description provided for @sendDetectedLightningPayment.
  ///
  /// In en, this message translates to:
  /// **'Lightning payment'**
  String get sendDetectedLightningPayment;

  /// No description provided for @sendDetectedLightningAddress.
  ///
  /// In en, this message translates to:
  /// **'Lightning address'**
  String get sendDetectedLightningAddress;

  /// No description provided for @sendDetectedBitcoinAddress.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin address'**
  String get sendDetectedBitcoinAddress;

  /// No description provided for @sendDetectedSpendingWalletAddress.
  ///
  /// In en, this message translates to:
  /// **'Spending wallet address'**
  String get sendDetectedSpendingWalletAddress;

  /// No description provided for @sendDetectedEthereumStyleAddress.
  ///
  /// In en, this message translates to:
  /// **'Ethereum style address'**
  String get sendDetectedEthereumStyleAddress;

  /// No description provided for @sendDetectedSolanaAddress.
  ///
  /// In en, this message translates to:
  /// **'Solana address'**
  String get sendDetectedSolanaAddress;

  /// No description provided for @walletImportedWithOthers.
  ///
  /// In en, this message translates to:
  /// **'{wallet} now appears with your other wallets.'**
  String walletImportedWithOthers(String wallet);

  /// No description provided for @sendCouldNotSend.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send. Nothing left your wallet.'**
  String get sendCouldNotSend;

  /// No description provided for @sendCouldNotComplete.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete this send. Check your activity before trying again.'**
  String get sendCouldNotComplete;

  /// No description provided for @sendCouldNotEstimateFee.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t estimate the fee. Try again.'**
  String get sendCouldNotEstimateFee;

  /// No description provided for @sendCouldNotPrepare.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare this payment. Check the amount and address, then try again.'**
  String get sendCouldNotPrepare;

  /// No description provided for @scanCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that code. Try again.'**
  String get scanCouldNotRead;

  /// No description provided for @scanCouldNotReadClipboard.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use what\'s on your clipboard. Copy the address or code again.'**
  String get scanCouldNotReadClipboard;

  /// No description provided for @walletImportCouldNotImport.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import this wallet. Try again.'**
  String get walletImportCouldNotImport;

  /// No description provided for @receiveWithdrawalCouldNotClaim.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t claim this withdrawal. Try again.'**
  String get receiveWithdrawalCouldNotClaim;

  /// No description provided for @hwCouldNotReadSignedFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file. Pick the signed transaction file and try again.'**
  String get hwCouldNotReadSignedFile;

  /// No description provided for @hwCouldNotSignWithJade.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign with your Jade. Check the device and try again.'**
  String get hwCouldNotSignWithJade;

  /// No description provided for @jadeErrorWrongDevice.
  ///
  /// In en, this message translates to:
  /// **'This Jade isn\'t the one paired with this wallet. Nothing was signed. Connect the paired Jade, or re-pair this one by updating the wallet\'s master fingerprint.'**
  String get jadeErrorWrongDevice;

  /// No description provided for @receiveOtherAssets.
  ///
  /// In en, this message translates to:
  /// **'Receive other assets'**
  String get receiveOtherAssets;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @claimFeeWarning.
  ///
  /// In en, this message translates to:
  /// **'Fee is more than half the deposit value'**
  String get claimFeeWarning;

  /// No description provided for @claimFeeExceedsDeposit.
  ///
  /// In en, this message translates to:
  /// **'Fee exceeds deposit value'**
  String get claimFeeExceedsDeposit;

  /// No description provided for @btcUsd.
  ///
  /// In en, this message translates to:
  /// **'BTC/USD'**
  String get btcUsd;

  /// No description provided for @longLabel.
  ///
  /// In en, this message translates to:
  /// **'Long'**
  String get longLabel;

  /// No description provided for @shortLabel.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get shortLabel;

  /// No description provided for @upLabel.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get upLabel;

  /// No description provided for @downLabel.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get downLabel;

  /// No description provided for @backUpBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your wallet'**
  String get backUpBannerTitle;

  /// No description provided for @backUpBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In case you lose your phone'**
  String get backUpBannerSubtitle;

  /// No description provided for @backUpBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get backUpBannerAction;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrder;

  /// No description provided for @requestRefund.
  ///
  /// In en, this message translates to:
  /// **'Request Refund'**
  String get requestRefund;

  /// No description provided for @unspent.
  ///
  /// In en, this message translates to:
  /// **'UNSPENT'**
  String get unspent;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @scanAnyQRCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Scan any QR code and we will try to figure it out.'**
  String get scanAnyQRCodeDescription;

  /// No description provided for @importFile.
  ///
  /// In en, this message translates to:
  /// **'Import File'**
  String get importFile;

  /// No description provided for @confirmImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get confirmImport;

  /// No description provided for @openBitcoinApp.
  ///
  /// In en, this message translates to:
  /// **'Open Bitcoin App'**
  String get openBitcoinApp;

  /// No description provided for @addWallet.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addWallet;

  /// No description provided for @recoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get recoveryPhrase;

  /// No description provided for @qrError.
  ///
  /// In en, this message translates to:
  /// **'QR Error'**
  String get qrError;

  /// No description provided for @satVb.
  ///
  /// In en, this message translates to:
  /// **'sat/vB'**
  String get satVb;

  /// No description provided for @method.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get method;

  /// No description provided for @payout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get payout;

  /// No description provided for @maxSlippage.
  ///
  /// In en, this message translates to:
  /// **'Max slippage'**
  String get maxSlippage;

  /// No description provided for @tapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get tapToRetry;

  /// No description provided for @resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolved;

  /// No description provided for @bid.
  ///
  /// In en, this message translates to:
  /// **'Bid'**
  String get bid;

  /// No description provided for @ask.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get ask;

  /// No description provided for @feeAmountSats.
  ///
  /// In en, this message translates to:
  /// **'{fee} sats'**
  String feeAmountSats(String fee);

  /// No description provided for @memoColon.
  ///
  /// In en, this message translates to:
  /// **'Memo: '**
  String get memoColon;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {err}'**
  String errorMessage(String err);

  /// No description provided for @ledgerBitcoinAppNotOpenMessage.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is connected, but the Bitcoin app isn\\\'t open yet.\\n\\nPlease open the Bitcoin app on your Ledger device, then tap Retry.'**
  String get ledgerBitcoinAppNotOpenMessage;

  /// No description provided for @selectWalletType.
  ///
  /// In en, this message translates to:
  /// **'Select Wallet Type'**
  String get selectWalletType;

  /// No description provided for @chooseDeviceForXpub.
  ///
  /// In en, this message translates to:
  /// **'Choose the device that generated this xpub'**
  String get chooseDeviceForXpub;

  /// No description provided for @connectViaBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Connect to {device} via Bluetooth'**
  String connectViaBluetooth(String device);

  /// No description provided for @scanBitcoinAddressQr.
  ///
  /// In en, this message translates to:
  /// **'Scan a Bitcoin address QR code'**
  String get scanBitcoinAddressQr;

  /// No description provided for @findBitcoinAddressToTrack.
  ///
  /// In en, this message translates to:
  /// **'Find the Bitcoin address you want to track.'**
  String get findBitcoinAddressToTrack;

  /// No description provided for @tapToScanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Tap below to scan the QR code.'**
  String get tapToScanQrCode;

  /// No description provided for @pasteBitcoinAddressFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste a Bitcoin address from clipboard'**
  String get pasteBitcoinAddressFromClipboard;

  /// No description provided for @searchPredictions.
  ///
  /// In en, this message translates to:
  /// **'Search predictions...'**
  String get searchPredictions;

  /// No description provided for @labelOptional.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get labelOptional;

  /// No description provided for @bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// No description provided for @connectJade.
  ///
  /// In en, this message translates to:
  /// **'Connect Jade'**
  String get connectJade;

  /// No description provided for @connectLedger.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger'**
  String get connectLedger;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @attention.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get attention;

  /// No description provided for @sdCard.
  ///
  /// In en, this message translates to:
  /// **'SD Card'**
  String get sdCard;

  /// No description provided for @utxoDust.
  ///
  /// In en, this message translates to:
  /// **'Dust'**
  String get utxoDust;

  /// No description provided for @coinMapAgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get coinMapAgeTitle;

  /// No description provided for @coinMapAgeDay.
  ///
  /// In en, this message translates to:
  /// **'Under a day'**
  String get coinMapAgeDay;

  /// No description provided for @coinMapAgeMonth.
  ///
  /// In en, this message translates to:
  /// **'Under a month'**
  String get coinMapAgeMonth;

  /// No description provided for @coinMapAgeYear.
  ///
  /// In en, this message translates to:
  /// **'Under a year'**
  String get coinMapAgeYear;

  /// No description provided for @coinMapAgeOlder.
  ///
  /// In en, this message translates to:
  /// **'Over a year'**
  String get coinMapAgeOlder;

  /// No description provided for @coinMapDustLegend.
  ///
  /// In en, this message translates to:
  /// **'Dust under {sats} sats'**
  String coinMapDustLegend(String sats);

  /// No description provided for @coinMapDustCoins.
  ///
  /// In en, this message translates to:
  /// **'Dust coins'**
  String get coinMapDustCoins;

  /// No description provided for @coinMapSmallCoins.
  ///
  /// In en, this message translates to:
  /// **'Smaller coins'**
  String get coinMapSmallCoins;

  /// No description provided for @coinMapAgeShortHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String coinMapAgeShortHours(int count);

  /// No description provided for @coinMapAgeShortDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String coinMapAgeShortDays(int count);

  /// No description provided for @coinMapAgeShortMonths.
  ///
  /// In en, this message translates to:
  /// **'{count}mo'**
  String coinMapAgeShortMonths(int count);

  /// No description provided for @coinMapAgeShortYears.
  ///
  /// In en, this message translates to:
  /// **'{count}y'**
  String coinMapAgeShortYears(int count);

  /// Shown in place of the instruction on the confirm PIN screen when the two entries differ.
  ///
  /// In en, this message translates to:
  /// **'That did not match. Enter it again.'**
  String get pinsDoNotMatchRetry;

  /// No description provided for @referrerFriendInvitedYou.
  ///
  /// In en, this message translates to:
  /// **'A friend invited you'**
  String get referrerFriendInvitedYou;

  /// No description provided for @accountYouEarnRate.
  ///
  /// In en, this message translates to:
  /// **'You earn {rate}%'**
  String accountYouEarnRate(String rate);

  /// No description provided for @accountInviteMoreForRate.
  ///
  /// In en, this message translates to:
  /// **'Invite {count} more friends to earn {rate}%'**
  String accountInviteMoreForRate(int count, int rate);

  /// No description provided for @restoreReconnectDeviceRow.
  ///
  /// In en, this message translates to:
  /// **'Connect your device again'**
  String get restoreReconnectDeviceRow;

  /// No description provided for @restoreAddAddressAgainRow.
  ///
  /// In en, this message translates to:
  /// **'Add the address again'**
  String get restoreAddAddressAgainRow;

  /// No description provided for @restoreImportWalletAgainRow.
  ///
  /// In en, this message translates to:
  /// **'Import the wallet again'**
  String get restoreImportWalletAgainRow;

  /// No description provided for @removeWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this phone?'**
  String removeWalletTitle(String name);

  /// No description provided for @removeWalletHardwareBody.
  ///
  /// In en, this message translates to:
  /// **'Your bitcoin stays on your device. You can add it again any time.'**
  String get removeWalletHardwareBody;

  /// No description provided for @removeWalletViewOnlyBody.
  ///
  /// In en, this message translates to:
  /// **'Kute stops showing this wallet. Nothing is spent or moved.'**
  String get removeWalletViewOnlyBody;

  /// No description provided for @removeWalletTrackedBody.
  ///
  /// In en, this message translates to:
  /// **'Kute stops watching this address. Nothing is spent or moved.'**
  String get removeWalletTrackedBody;

  /// No description provided for @removeWalletHotBody.
  ///
  /// In en, this message translates to:
  /// **'You can only get it back with its recovery phrase. Make sure you have it written down.'**
  String get removeWalletHotBody;

  /// No description provided for @removeWalletPasskeyBody.
  ///
  /// In en, this message translates to:
  /// **'You can add it back later with the account you created it with.'**
  String get removeWalletPasskeyBody;

  /// No description provided for @removeWalletAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeWalletAction;

  /// No description provided for @forgotPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot your PIN?'**
  String get forgotPinTitle;

  /// No description provided for @forgotPinBody.
  ///
  /// In en, this message translates to:
  /// **'Add it back with your passkey or 12 words.'**
  String get forgotPinBody;

  /// No description provided for @forgotPinAction.
  ///
  /// In en, this message translates to:
  /// **'Remove and start over'**
  String get forgotPinAction;

  /// No description provided for @walletTypeHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallet'**
  String get walletTypeHardware;

  /// No description provided for @walletTypeViewOnly.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get walletTypeViewOnly;

  /// No description provided for @walletTypeTracked.
  ///
  /// In en, this message translates to:
  /// **'Tracked address'**
  String get walletTypeTracked;

  /// No description provided for @walletTypeBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin wallet'**
  String get walletTypeBitcoin;

  /// No description provided for @walletTypeKute.
  ///
  /// In en, this message translates to:
  /// **'Kute wallet'**
  String get walletTypeKute;

  /// No description provided for @walletPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Wallet public key'**
  String get walletPublicKey;

  /// No description provided for @walletPublicKeyShowFull.
  ///
  /// In en, this message translates to:
  /// **'Show full key'**
  String get walletPublicKeyShowFull;

  /// No description provided for @walletsNeverShareWordsPlain.
  ///
  /// In en, this message translates to:
  /// **'Never share these words. Anyone who has them can take everything in this wallet.'**
  String get walletsNeverShareWordsPlain;

  /// No description provided for @viewOnlyWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'View only wallet'**
  String get viewOnlyWalletTitle;

  /// No description provided for @seedWordsViewOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'This wallet is view only. Its keys are not on this phone, so there is no recovery phrase to show.'**
  String get seedWordsViewOnlyNote;

  /// No description provided for @exportCollectingActivity.
  ///
  /// In en, this message translates to:
  /// **'Collecting your activity'**
  String get exportCollectingActivity;

  /// No description provided for @exportBuildingReport.
  ///
  /// In en, this message translates to:
  /// **'Building your report'**
  String get exportBuildingReport;

  /// No description provided for @exportFormatPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get exportFormatPdf;

  /// No description provided for @exportFormatCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportFormatCsv;

  /// No description provided for @settingsAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Support info and technical options'**
  String get settingsAdvancedSubtitle;

  /// No description provided for @settingsServerDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsServerDefault;

  /// No description provided for @settingsServerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsServerCustom;

  /// No description provided for @settingsServerCustomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own server'**
  String get settingsServerCustomSubtitle;

  /// No description provided for @settingsMoreServers.
  ///
  /// In en, this message translates to:
  /// **'More servers'**
  String get settingsMoreServers;

  /// No description provided for @settingsServerAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get settingsServerAddress;

  /// No description provided for @settingsServerAddressExample.
  ///
  /// In en, this message translates to:
  /// **'For example electrum.example.com:50002'**
  String get settingsServerAddressExample;

  /// No description provided for @settingsServerFormatError.
  ///
  /// In en, this message translates to:
  /// **'Enter a server address like electrum.example.com:50002 or an https address.'**
  String get settingsServerFormatError;

  /// No description provided for @importScanQrDescription.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code shown on your device'**
  String get importScanQrDescription;

  /// No description provided for @importFileDescription.
  ///
  /// In en, this message translates to:
  /// **'Load the file your device exported'**
  String get importFileDescription;

  /// No description provided for @importPasteDescription.
  ///
  /// In en, this message translates to:
  /// **'Paste the key here'**
  String get importPasteDescription;

  /// No description provided for @importPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the public key from your device'**
  String get importPasteHint;

  /// No description provided for @importKeyLooksGood.
  ///
  /// In en, this message translates to:
  /// **'Looks good'**
  String get importKeyLooksGood;

  /// No description provided for @importCustomPath.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get importCustomPath;

  /// No description provided for @importWhereIsQr.
  ///
  /// In en, this message translates to:
  /// **'Where do I find the QR code?'**
  String get importWhereIsQr;

  /// No description provided for @scannerKeepInFrame.
  ///
  /// In en, this message translates to:
  /// **'Keep the code in the frame'**
  String get scannerKeepInFrame;

  /// No description provided for @scannerPointAtCode.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code'**
  String get scannerPointAtCode;

  /// No description provided for @trackAddressPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a Bitcoin address'**
  String get trackAddressPasteHint;

  /// No description provided for @trackAddressWatchOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'You can watch this address, but you can\'t send from it.'**
  String get trackAddressWatchOnlyNote;

  /// No description provided for @trackAddressHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch a Bitcoin address'**
  String get trackAddressHeroTitle;

  /// No description provided for @trackAddressHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See its balance and activity in Kute.'**
  String get trackAddressHeroSubtitle;

  /// No description provided for @recoverWithAccount.
  ///
  /// In en, this message translates to:
  /// **'Use your {account}'**
  String recoverWithAccount(String account);

  /// No description provided for @recoverWithPhrase.
  ///
  /// In en, this message translates to:
  /// **'Use your recovery phrase'**
  String get recoverWithPhrase;

  /// No description provided for @settingsBackupAndRecovery.
  ///
  /// In en, this message translates to:
  /// **'Backup and recovery'**
  String get settingsBackupAndRecovery;

  /// No description provided for @settingsBackupAndRecoverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View your recovery phrase'**
  String get settingsBackupAndRecoverySubtitle;

  /// No description provided for @recoveryPhraseCopied.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase copied. The clipboard clears in 60 seconds.'**
  String get recoveryPhraseCopied;

  /// No description provided for @recoveryPhraseLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t show the recovery phrase for {walletName}. Please try again.'**
  String recoveryPhraseLoadFailed(String walletName);

  /// No description provided for @recoveryPhraseLoadFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your recovery phrase. Please try again.'**
  String get recoveryPhraseLoadFailedGeneric;

  /// No description provided for @enterPinToViewRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to view the recovery phrase'**
  String get enterPinToViewRecoveryPhrase;

  /// No description provided for @recoveryPhraseInvalid.
  ///
  /// In en, this message translates to:
  /// **'These words don\'t form a valid recovery phrase. Check each word and try again.'**
  String get recoveryPhraseInvalid;

  /// No description provided for @recoverWithRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery phrase to bring your wallet back.'**
  String get recoverWithRecoveryPhrase;

  /// No description provided for @recoveryPhraseSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get recoveryPhraseSectionLabel;

  /// No description provided for @recoverChoicePasskeyLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a wallet saved with your account. Use your recovery phrase instead.'**
  String get recoverChoicePasskeyLookupFailed;

  /// No description provided for @recoverChoicePasskeyRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore that wallet. Use your recovery phrase instead.'**
  String get recoverChoicePasskeyRestoreFailed;

  /// No description provided for @recoverChoiceNoPasskeyWallet.
  ///
  /// In en, this message translates to:
  /// **'No wallet was found for this account. Use your recovery phrase instead.'**
  String get recoverChoiceNoPasskeyWallet;

  /// No description provided for @passkeyChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with {method}'**
  String passkeyChoiceTitle(String method);

  /// No description provided for @passkeyChoiceTitleNoBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Set up your wallet'**
  String get passkeyChoiceTitleNoBiometrics;

  /// No description provided for @passkeyChoiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kute uses {method} to protect your wallet. There is nothing to write down.'**
  String passkeyChoiceSubtitle(String method);

  /// No description provided for @passkeyChoiceToggle.
  ///
  /// In en, this message translates to:
  /// **'Use {method}'**
  String passkeyChoiceToggle(String method);

  /// No description provided for @passkeyChoiceFooter.
  ///
  /// In en, this message translates to:
  /// **'Your login is saved with your {account}. Keep that account and you can get back in on a new phone.'**
  String passkeyChoiceFooter(String account);

  /// No description provided for @passkeyChoiceAppleAccount.
  ///
  /// In en, this message translates to:
  /// **'Apple account'**
  String get passkeyChoiceAppleAccount;

  /// No description provided for @passkeyChoiceGoogleAccount.
  ///
  /// In en, this message translates to:
  /// **'Google account'**
  String get passkeyChoiceGoogleAccount;

  /// No description provided for @passkeyChoiceCancelled.
  ///
  /// In en, this message translates to:
  /// **'Setup cancelled. Nothing was created.'**
  String get passkeyChoiceCancelled;

  /// No description provided for @passkeyChoiceFallbackWords.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t set up {method}. Your wallet was created with recovery words instead.'**
  String passkeyChoiceFallbackWords(String method);

  /// No description provided for @biometricFaceId.
  ///
  /// In en, this message translates to:
  /// **'Face ID'**
  String get biometricFaceId;

  /// No description provided for @biometricTouchId.
  ///
  /// In en, this message translates to:
  /// **'Touch ID'**
  String get biometricTouchId;

  /// No description provided for @biometricFingerprint.
  ///
  /// In en, this message translates to:
  /// **'fingerprint'**
  String get biometricFingerprint;

  /// No description provided for @biometricFaceUnlock.
  ///
  /// In en, this message translates to:
  /// **'face unlock'**
  String get biometricFaceUnlock;

  /// No description provided for @confirmationAddressTracked.
  ///
  /// In en, this message translates to:
  /// **'Address added'**
  String get confirmationAddressTracked;

  /// No description provided for @errorCopyCreateWallet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create your wallet. Please try again.'**
  String get errorCopyCreateWallet;

  /// No description provided for @errorCopySetPin.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your PIN. Please try again.'**
  String get errorCopySetPin;

  /// No description provided for @errorCopyUnlock.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unlock Kute. Please try again.'**
  String get errorCopyUnlock;

  /// No description provided for @errorCopyRecoverWallet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t recover this wallet. Check the words and try again.'**
  String get errorCopyRecoverWallet;

  /// No description provided for @errorCopyImportWallet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add this wallet. Please try again.'**
  String get errorCopyImportWallet;

  /// No description provided for @errorCopyTrackAddress.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add this address. Please try again.'**
  String get errorCopyTrackAddress;

  /// No description provided for @errorCopyReadFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file. Please try again.'**
  String get errorCopyReadFile;

  /// No description provided for @errorCopyExport.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build your report. Please try again.'**
  String get errorCopyExport;

  /// No description provided for @errorCopyChangePin.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your PIN. Please try again.'**
  String get errorCopyChangePin;

  /// No description provided for @restoreWriteFailedPlain.
  ///
  /// In en, this message translates to:
  /// **'Kute couldn\'t save this wallet on this phone. Nothing was deleted. Try again.'**
  String get restoreWriteFailedPlain;

  /// No description provided for @swapRouteTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This route is temporarily unavailable. Please try again later.'**
  String get swapRouteTemporarilyUnavailable;

  /// No description provided for @receiveAssetTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Receiving this asset is temporarily unavailable.'**
  String get receiveAssetTemporarilyUnavailable;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmpty;

  /// No description provided for @pleaseSetUpPINFirst.
  ///
  /// In en, this message translates to:
  /// **'Please set up your PIN first'**
  String get pleaseSetUpPINFirst;

  /// No description provided for @connectingToDevice.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {device}...'**
  String connectingToDevice(String device);

  /// No description provided for @failedToRetrieveWalletData.
  ///
  /// In en, this message translates to:
  /// **'Failed to retrieve wallet data.'**
  String get failedToRetrieveWalletData;

  /// No description provided for @enterPINOnJadeDevice.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN on the Jade device...'**
  String get enterPINOnJadeDevice;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get orderCancelled;

  /// No description provided for @cannotSellTokenUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot sell: token ID unavailable'**
  String get cannotSellTokenUnavailable;

  /// No description provided for @soldShares.
  ///
  /// In en, this message translates to:
  /// **'Sold {shares} shares of {outcome}'**
  String soldShares(String shares, String outcome);

  /// No description provided for @loadingAccount.
  ///
  /// In en, this message translates to:
  /// **'Loading your account...'**
  String get loadingAccount;

  /// No description provided for @outcomeNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This outcome is not available for trading yet.'**
  String get outcomeNotAvailable;

  /// No description provided for @orderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Order placed: {shares} shares of {outcome}'**
  String orderPlaced(String shares, String outcome);

  /// No description provided for @tradingUnavailableRegion.
  ///
  /// In en, this message translates to:
  /// **'Trading is restricted in the region your internet connection appears to be in. If that isn\'t where you are, check your network or VPN settings and try again.'**
  String get tradingUnavailableRegion;

  /// No description provided for @ohlcOpen.
  ///
  /// In en, this message translates to:
  /// **'Open: '**
  String get ohlcOpen;

  /// No description provided for @ohlcHigh.
  ///
  /// In en, this message translates to:
  /// **'High: '**
  String get ohlcHigh;

  /// No description provided for @ohlcLow.
  ///
  /// In en, this message translates to:
  /// **'Low: '**
  String get ohlcLow;

  /// No description provided for @ohlcClose.
  ///
  /// In en, this message translates to:
  /// **'Close: '**
  String get ohlcClose;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @betaSurveyTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us a bit about you'**
  String get betaSurveyTitle;

  /// No description provided for @betaSurveySubtitle.
  ///
  /// In en, this message translates to:
  /// **'This helps us tailor Kute to people like you. Totally optional.'**
  String get betaSurveySubtitle;

  /// No description provided for @betaSurveyGender.
  ///
  /// In en, this message translates to:
  /// **'GENDER'**
  String get betaSurveyGender;

  /// No description provided for @betaSurveyMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get betaSurveyMale;

  /// No description provided for @betaSurveyFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get betaSurveyFemale;

  /// No description provided for @betaSurveyAge.
  ///
  /// In en, this message translates to:
  /// **'AGE RANGE'**
  String get betaSurveyAge;

  /// No description provided for @betaSurveyContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get betaSurveyContinue;

  /// No description provided for @betaSurveySkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get betaSurveySkip;

  /// No description provided for @cashAppMinPerOrder.
  ///
  /// In en, this message translates to:
  /// **'The minimum is {amount} per order.'**
  String cashAppMinPerOrder(String amount);

  /// No description provided for @cashAppMaxPerOrder.
  ///
  /// In en, this message translates to:
  /// **'The maximum is {amount} per order.'**
  String cashAppMaxPerOrder(String amount);

  /// No description provided for @cashAppWaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your payment'**
  String get cashAppWaitingPayment;

  /// No description provided for @cashAppScanInvoice.
  ///
  /// In en, this message translates to:
  /// **'Or scan the invoice with any Lightning wallet.'**
  String get cashAppScanInvoice;

  /// No description provided for @cashAppCopyInvoice.
  ///
  /// In en, this message translates to:
  /// **'Copy invoice'**
  String get cashAppCopyInvoice;

  /// No description provided for @cashAppInvoiceCopied.
  ///
  /// In en, this message translates to:
  /// **'Invoice copied'**
  String get cashAppInvoiceCopied;

  /// No description provided for @cashAppWaitingForApp.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Cash App'**
  String get cashAppWaitingForApp;

  /// No description provided for @cashAppOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Open Cash App again'**
  String get cashAppOpenAgain;

  /// No description provided for @cashAppRefundNote.
  ///
  /// In en, this message translates to:
  /// **'If you already paid, the amount will be refunded.'**
  String get cashAppRefundNote;

  /// No description provided for @cashAppPaymentWindowEnded.
  ///
  /// In en, this message translates to:
  /// **'Payment window ended'**
  String get cashAppPaymentWindowEnded;

  /// No description provided for @cashAppPaymentWindowEndedChecking.
  ///
  /// In en, this message translates to:
  /// **'Payment window ended. Checking final status.'**
  String get cashAppPaymentWindowEndedChecking;

  /// No description provided for @cashAppCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get cashAppCheckStatus;

  /// No description provided for @cashAppCreateNewPurchase.
  ///
  /// In en, this message translates to:
  /// **'Create new purchase'**
  String get cashAppCreateNewPurchase;

  /// No description provided for @cashAppPreviousPurchaseTracked.
  ///
  /// In en, this message translates to:
  /// **'The previous purchase stays in Activity. Any payment already sent will still be tracked.'**
  String get cashAppPreviousPurchaseTracked;

  /// No description provided for @cashAppCancelPurchase.
  ///
  /// In en, this message translates to:
  /// **'Cancel purchase'**
  String get cashAppCancelPurchase;

  /// No description provided for @cashAppCancelPurchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this purchase?'**
  String get cashAppCancelPurchaseTitle;

  /// No description provided for @cashAppCancelPurchaseBody.
  ///
  /// In en, this message translates to:
  /// **'The invoice is removed from Activity and nothing more is expected from it. Only cancel if you have not sent the payment in Cash App. A payment already sent still arrives.'**
  String get cashAppCancelPurchaseBody;

  /// No description provided for @cashAppKeepPurchase.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get cashAppKeepPurchase;

  /// No description provided for @cashAppPurchaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled'**
  String get cashAppPurchaseCancelled;

  /// No description provided for @cashAppInvoice.
  ///
  /// In en, this message translates to:
  /// **'Cash App invoice'**
  String get cashAppInvoice;

  /// No description provided for @cashAppBitcoinPurchased.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin purchased'**
  String get cashAppBitcoinPurchased;

  /// No description provided for @cashAppDollarsPurchased.
  ///
  /// In en, this message translates to:
  /// **'Dollars purchased'**
  String get cashAppDollarsPurchased;

  /// No description provided for @coldWalletAddressUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not get a receive address for {name}. Try again.'**
  String coldWalletAddressUnavailable(String name);

  /// No description provided for @openCashApp.
  ///
  /// In en, this message translates to:
  /// **'Open Cash App'**
  String get openCashApp;

  /// No description provided for @purchaseProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing your purchase...'**
  String get purchaseProcessing;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed'**
  String get purchaseFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLink;

  /// No description provided for @deletePayLink.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deletePayLink;

  /// No description provided for @receiveInto.
  ///
  /// In en, this message translates to:
  /// **'Receive into'**
  String get receiveInto;

  /// No description provided for @receiveScanOrShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan or share this code to get paid.'**
  String get receiveScanOrShareSubtitle;

  /// No description provided for @receiveSyncingWalletCaption.
  ///
  /// In en, this message translates to:
  /// **'Syncing your wallet. The address will appear in a moment.'**
  String get receiveSyncingWalletCaption;

  /// No description provided for @receiveBeneficiary.
  ///
  /// In en, this message translates to:
  /// **'Beneficiary'**
  String get receiveBeneficiary;

  /// No description provided for @receiveAssetOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'{asset} on {network}'**
  String receiveAssetOnNetwork(String asset, String network);

  /// No description provided for @receiveFailedToGetRate.
  ///
  /// In en, this message translates to:
  /// **'Failed to get rate'**
  String get receiveFailedToGetRate;

  /// No description provided for @receiveNetworkErrorTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Network error. Tap to retry.'**
  String get receiveNetworkErrorTapToRetry;

  /// No description provided for @receiveUsdcWalletNotReady.
  ///
  /// In en, this message translates to:
  /// **'Your Predictions account is still setting up. Try again in a moment.'**
  String get receiveUsdcWalletNotReady;

  /// No description provided for @receiveFundsLandAsBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Funds land on your wallet as Bitcoin.'**
  String get receiveFundsLandAsBitcoin;

  /// No description provided for @receiveConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed.'**
  String get receiveConnectionFailed;

  /// No description provided for @receiveAuthenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed.'**
  String get receiveAuthenticationFailed;

  /// No description provided for @receiveFailedToVerifyAddressOnJade.
  ///
  /// In en, this message translates to:
  /// **'Failed to verify address on Jade.'**
  String get receiveFailedToVerifyAddressOnJade;

  /// No description provided for @receivePickANewHandle.
  ///
  /// In en, this message translates to:
  /// **'Pick a new handle people will use to pay you.'**
  String get receivePickANewHandle;

  /// No description provided for @receiveQrFormatUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get receiveQrFormatUnified;

  /// No description provided for @receiveQrFormatBitcoinOnly.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin only'**
  String get receiveQrFormatBitcoinOnly;

  /// No description provided for @receiveQrFormatLightningOnly.
  ///
  /// In en, this message translates to:
  /// **'Lightning only'**
  String get receiveQrFormatLightningOnly;

  /// No description provided for @receiveQrCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get receiveQrCodeLabel;

  /// No description provided for @receiveCopyAndPaste.
  ///
  /// In en, this message translates to:
  /// **'Copy & Paste'**
  String get receiveCopyAndPaste;

  /// No description provided for @receiveSigningCancelledOrFailed.
  ///
  /// In en, this message translates to:
  /// **'Signing was cancelled or failed.'**
  String get receiveSigningCancelledOrFailed;

  /// No description provided for @receiveVerifyDetailsMatchDevice.
  ///
  /// In en, this message translates to:
  /// **'Verify these details match what your device displays.'**
  String get receiveVerifyDetailsMatchDevice;

  /// No description provided for @receiveSendingBitcoinTo.
  ///
  /// In en, this message translates to:
  /// **'Sending {amount} {unit} of Bitcoin to {address}'**
  String receiveSendingBitcoinTo(String amount, String unit, String address);

  /// No description provided for @receiveUsingQrPinUnlockJade.
  ///
  /// In en, this message translates to:
  /// **'Using QR PIN? Unlock your Jade here first'**
  String get receiveUsingQrPinUnlockJade;

  /// No description provided for @receiveConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get receiveConnecting;

  /// No description provided for @receiveVerifyOnJadeScreenBeforeConfirming.
  ///
  /// In en, this message translates to:
  /// **'Verify the address and amount on your Jade screen before confirming.'**
  String get receiveVerifyOnJadeScreenBeforeConfirming;

  /// No description provided for @receiveVerifyOnLedgerScreenBeforeConfirming.
  ///
  /// In en, this message translates to:
  /// **'Verify the address and amount on your Ledger screen before confirming.'**
  String get receiveVerifyOnLedgerScreenBeforeConfirming;

  /// No description provided for @receiveWithdrawalNoBalance.
  ///
  /// In en, this message translates to:
  /// **'This withdrawal request has no available balance.'**
  String get receiveWithdrawalNoBalance;

  /// No description provided for @receiveLightningWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Lightning withdrawal'**
  String get receiveLightningWithdrawal;

  /// No description provided for @receiveWithdrawalLinkAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This withdrawal link has already been used.'**
  String get receiveWithdrawalLinkAlreadyUsed;

  /// No description provided for @receiveWithdrawalLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'This withdrawal link has expired.'**
  String get receiveWithdrawalLinkExpired;

  /// No description provided for @receiveWithdrawalServiceUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the withdrawal service. Check your connection and try again.'**
  String get receiveWithdrawalServiceUnreachable;

  /// No description provided for @receiveNoQrCodeFoundInImage.
  ///
  /// In en, this message translates to:
  /// **'No QR code found in that image.'**
  String get receiveNoQrCodeFoundInImage;

  /// No description provided for @receiveCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get receiveCameraUnavailable;

  /// No description provided for @receiveProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get receiveProcessing;

  /// No description provided for @receiveGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get receiveGallery;

  /// No description provided for @walletsSpendingAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Spending account'**
  String get walletsSpendingAccountSection;

  /// No description provided for @walletsHardwareWalletsSection.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallets'**
  String get walletsHardwareWalletsSection;

  /// No description provided for @walletsWatchAnAddressSection.
  ///
  /// In en, this message translates to:
  /// **'Watch an address'**
  String get walletsWatchAnAddressSection;

  /// No description provided for @walletsBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get walletsBank;

  /// No description provided for @walletsBankConnectionsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Bank connections. Coming soon.'**
  String get walletsBankConnectionsComingSoon;

  /// No description provided for @walletsExchange.
  ///
  /// In en, this message translates to:
  /// **'Exchange'**
  String get walletsExchange;

  /// No description provided for @walletsExchangeImportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Exchange import. Coming soon.'**
  String get walletsExchangeImportComingSoon;

  /// No description provided for @walletsWalletConnect.
  ///
  /// In en, this message translates to:
  /// **'WalletConnect'**
  String get walletsWalletConnect;

  /// No description provided for @walletsWalletConnectComingSoon.
  ///
  /// In en, this message translates to:
  /// **'WalletConnect. Coming soon.'**
  String get walletsWalletConnectComingSoon;

  /// No description provided for @walletsNostrWalletConnect.
  ///
  /// In en, this message translates to:
  /// **'Nostr Wallet Connect'**
  String get walletsNostrWalletConnect;

  /// No description provided for @walletsNostrWalletConnectComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Nostr Wallet Connect. Coming soon.'**
  String get walletsNostrWalletConnectComingSoon;

  /// No description provided for @walletsSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get walletsSoon;

  /// No description provided for @walletsCouldntConnectToDevice.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t connect to your {device}.'**
  String walletsCouldntConnectToDevice(String device);

  /// No description provided for @walletsConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get walletsConnectionFailed;

  /// No description provided for @walletsAuthenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get walletsAuthenticationFailed;

  /// No description provided for @walletsJadeUnlockExportXpub.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Jade and navigate to Options > Wallet > Export Xpub.'**
  String get walletsJadeUnlockExportXpub;

  /// No description provided for @walletsUsingQrPinUnlockJade.
  ///
  /// In en, this message translates to:
  /// **'Using QR PIN? Unlock your Jade here first'**
  String get walletsUsingQrPinUnlockJade;

  /// No description provided for @walletsJadeQrAppearScan.
  ///
  /// In en, this message translates to:
  /// **'A QR code will appear on the Jade screen. Tap below to scan it.'**
  String get walletsJadeQrAppearScan;

  /// No description provided for @walletsNavigateExportXpubQr.
  ///
  /// In en, this message translates to:
  /// **'On your {device}, navigate to Export Xpub and display the QR code.'**
  String walletsNavigateExportXpubQr(String device);

  /// No description provided for @walletsTapToScanQrFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Tap below to scan the QR code from your device.'**
  String get walletsTapToScanQrFromDevice;

  /// No description provided for @walletsTurnOnJadeBluetoothEnabled.
  ///
  /// In en, this message translates to:
  /// **'Turn on your Jade and make sure Bluetooth is enabled.'**
  String get walletsTurnOnJadeBluetoothEnabled;

  /// No description provided for @walletsTapConnectEnterPinJade.
  ///
  /// In en, this message translates to:
  /// **'Tap below to connect. Enter your PIN when prompted on the Jade.'**
  String get walletsTapConnectEnterPinJade;

  /// No description provided for @walletsCloseLedgerLiveCompletely.
  ///
  /// In en, this message translates to:
  /// **'Close Ledger Live completely on your computer and phone.'**
  String get walletsCloseLedgerLiveCompletely;

  /// No description provided for @walletsTurnOnUnlockLedger.
  ///
  /// In en, this message translates to:
  /// **'Turn on and unlock your Ledger device.'**
  String get walletsTurnOnUnlockLedger;

  /// No description provided for @walletsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get walletsAdvanced;

  /// No description provided for @walletsAddressType.
  ///
  /// In en, this message translates to:
  /// **'Address Type'**
  String get walletsAddressType;

  /// No description provided for @walletsAddressTypeHelper.
  ///
  /// In en, this message translates to:
  /// **'Most modern wallets use Native SegWit. Only change this if your device tells you to.'**
  String get walletsAddressTypeHelper;

  /// No description provided for @walletsDerivationPath.
  ///
  /// In en, this message translates to:
  /// **'Derivation Path'**
  String get walletsDerivationPath;

  /// No description provided for @walletsUsingCustomPathWarning.
  ///
  /// In en, this message translates to:
  /// **'Using custom path. Make sure it matches your hardware wallet.'**
  String get walletsUsingCustomPathWarning;

  /// No description provided for @walletsConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get walletsConnect;

  /// No description provided for @walletsImportXpubExplainer.
  ///
  /// In en, this message translates to:
  /// **'Connect your device to import its public key. Kute can show balances and receive funds while your keys stay on the device.'**
  String get walletsImportXpubExplainer;

  /// No description provided for @walletsInvalidKeyHint.
  ///
  /// In en, this message translates to:
  /// **'This does not look like a valid public key yet'**
  String get walletsInvalidKeyHint;

  /// No description provided for @walletsInvalidAddressHint.
  ///
  /// In en, this message translates to:
  /// **'This does not look like a valid Bitcoin address yet'**
  String get walletsInvalidAddressHint;

  /// No description provided for @walletsOtherWaysToImport.
  ///
  /// In en, this message translates to:
  /// **'Other ways to import'**
  String get walletsOtherWaysToImport;

  /// No description provided for @walletsFixTurnOnJadeUnlockPin.
  ///
  /// In en, this message translates to:
  /// **'Turn on your Jade and unlock it with your PIN.'**
  String get walletsFixTurnOnJadeUnlockPin;

  /// No description provided for @walletsFixBluetoothOnBothDevices.
  ///
  /// In en, this message translates to:
  /// **'Make sure Bluetooth is on for both devices.'**
  String get walletsFixBluetoothOnBothDevices;

  /// No description provided for @walletsFixKeepJadeClose.
  ///
  /// In en, this message translates to:
  /// **'Keep the Jade close to your phone.'**
  String get walletsFixKeepJadeClose;

  /// No description provided for @walletsFixCloseLedgerLive.
  ///
  /// In en, this message translates to:
  /// **'Close Ledger Live on your computer and phone.'**
  String get walletsFixCloseLedgerLive;

  /// No description provided for @walletsFixUnlockLedgerOpenBitcoinApp.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger and open the Bitcoin app.'**
  String get walletsFixUnlockLedgerOpenBitcoinApp;

  /// No description provided for @walletsTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get walletsTryAgain;

  /// No description provided for @walletsSupportedModels.
  ///
  /// In en, this message translates to:
  /// **'Supported models'**
  String get walletsSupportedModels;

  /// No description provided for @walletsExportWalletToFile.
  ///
  /// In en, this message translates to:
  /// **'On your {device}, export your wallet to a file (SD card or storage).'**
  String walletsExportWalletToFile(String device);

  /// No description provided for @walletsTapToImportFile.
  ///
  /// In en, this message translates to:
  /// **'Tap below to import the file.'**
  String get walletsTapToImportFile;

  /// No description provided for @walletsTrackedAddress.
  ///
  /// In en, this message translates to:
  /// **'Tracked address'**
  String get walletsTrackedAddress;

  /// No description provided for @walletsNoRecoveryPhraseStored.
  ///
  /// In en, this message translates to:
  /// **'No recovery phrase stored for this wallet.'**
  String get walletsNoRecoveryPhraseStored;

  /// No description provided for @walletsNoAddressStored.
  ///
  /// In en, this message translates to:
  /// **'No address stored for this wallet.'**
  String get walletsNoAddressStored;

  /// No description provided for @walletsSafeToShareViewOnly.
  ///
  /// In en, this message translates to:
  /// **'Safe to share. Anyone with this can see this wallet\'s balance and history but cannot spend.'**
  String get walletsSafeToShareViewOnly;

  /// No description provided for @walletsNoXpubStored.
  ///
  /// In en, this message translates to:
  /// **'No xpub stored for this wallet.'**
  String get walletsNoXpubStored;

  /// No description provided for @walletsXpubSafeToShare.
  ///
  /// In en, this message translates to:
  /// **'Safe to share for watch-only apps. Does not grant spending access.'**
  String get walletsXpubSafeToShare;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountName;

  /// No description provided for @recoveryMethodDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how you saved access to your account.'**
  String get recoveryMethodDescription;

  /// No description provided for @walletsCheckingYourDevice.
  ///
  /// In en, this message translates to:
  /// **'Checking your device…'**
  String get walletsCheckingYourDevice;

  /// No description provided for @walletsNotAvailableOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device.'**
  String get walletsNotAvailableOnDevice;

  /// No description provided for @walletsNoRecoveryPhraseToManage.
  ///
  /// In en, this message translates to:
  /// **'No recovery phrase to manage.'**
  String get walletsNoRecoveryPhraseToManage;

  /// No description provided for @walletsWriteDown12WordsInstead.
  ///
  /// In en, this message translates to:
  /// **'You\'ll write down a 12-word recovery phrase instead.'**
  String get walletsWriteDown12WordsInstead;

  /// No description provided for @walletsShown12WordsWarning.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be shown a 12-word recovery phrase. Anyone who has it can access your wallet. Write it down somewhere safe.'**
  String get walletsShown12WordsWarning;

  /// No description provided for @walletsShareCodeEarnDescription.
  ///
  /// In en, this message translates to:
  /// **'Share your code and earn up to {rate} of what Kute makes from friends you invite.'**
  String walletsShareCodeEarnDescription(String rate);

  /// No description provided for @walletsShareCodeEarnDescriptionNoRate.
  ///
  /// In en, this message translates to:
  /// **'Share your code and earn a share of what Kute makes from friends you invite.'**
  String get walletsShareCodeEarnDescriptionNoRate;

  /// No description provided for @walletsShareTextWithLink.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my link and get {discount} off Kute fees: {link}'**
  String walletsShareTextWithLink(String link, String discount);

  /// No description provided for @walletsShareTextWithLinkNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my link: {link}'**
  String walletsShareTextWithLinkNoDiscount(String link);

  /// No description provided for @walletsShareTextWithCodeNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my code {code}.'**
  String walletsShareTextWithCodeNoDiscount(String code);

  /// No description provided for @walletsShareTextWithCode.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my code {code} and get {discount} off Kute fees.'**
  String walletsShareTextWithCode(String code, String discount);

  /// No description provided for @walletsConfirmFriendInvite.
  ///
  /// In en, this message translates to:
  /// **'Confirm your friend\'s invite to get {discount} off Kute fees.'**
  String walletsConfirmFriendInvite(String discount);

  /// No description provided for @walletsConfirmFriendInviteNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'Confirm your friend\'s invite.'**
  String get walletsConfirmFriendInviteNoDiscount;

  /// No description provided for @walletsEnterFriendCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'If a friend invited you, enter their code to get {discount} off Kute fees.'**
  String walletsEnterFriendCodeDescription(String discount);

  /// No description provided for @walletsEnterFriendCodeDescriptionNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'If a friend invited you, enter their code.'**
  String get walletsEnterFriendCodeDescriptionNoDiscount;

  /// No description provided for @accountEarn.
  ///
  /// In en, this message translates to:
  /// **'Earn'**
  String get accountEarn;

  /// No description provided for @accountInviteFriendsEarnShare.
  ///
  /// In en, this message translates to:
  /// **'Invite friends and earn a share of what Kute makes from them.'**
  String get accountInviteFriendsEarnShare;

  /// No description provided for @accountCouldntLoadEarnData.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your Earn data'**
  String get accountCouldntLoadEarnData;

  /// No description provided for @accountTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get accountTryAgain;

  /// No description provided for @accountCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get accountCopyLink;

  /// No description provided for @accountLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get accountLinkCopied;

  /// No description provided for @accountCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get accountCodeCopied;

  /// No description provided for @accountShareTextWithLink.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my link and get {discount} off Kute fees: {link}'**
  String accountShareTextWithLink(String link, String discount);

  /// No description provided for @accountShareTextWithCode.
  ///
  /// In en, this message translates to:
  /// **'I\'m using Kute. Join with my code {code} and get {discount} off Kute fees.'**
  String accountShareTextWithCode(String code, String discount);

  /// No description provided for @accountUsersWithYourCode.
  ///
  /// In en, this message translates to:
  /// **'Users with your code'**
  String get accountUsersWithYourCode;

  /// No description provided for @accountPendingPayout.
  ///
  /// In en, this message translates to:
  /// **'Pending payout'**
  String get accountPendingPayout;

  /// No description provided for @accountPaidToDate.
  ///
  /// In en, this message translates to:
  /// **'Paid to date'**
  String get accountPaidToDate;

  /// No description provided for @accountEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get accountEarnings;

  /// No description provided for @accountNotEnoughDataYet.
  ///
  /// In en, this message translates to:
  /// **'Not enough data yet'**
  String get accountNotEnoughDataYet;

  /// No description provided for @accountDaysAbbrev.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String accountDaysAbbrev(int days);

  /// No description provided for @accountRuleEarnings.
  ///
  /// In en, this message translates to:
  /// **'You earn {rate} of the fees your friends generate.'**
  String accountRuleEarnings(String rate);

  /// No description provided for @accountRuleEarningsLadder.
  ///
  /// In en, this message translates to:
  /// **'You earn {rate} of the fees your friends generate, {ladder}.'**
  String accountRuleEarningsLadder(String rate, String ladder);

  /// No description provided for @accountRuleEarningsStep.
  ///
  /// In en, this message translates to:
  /// **'{rate} at {count} friends'**
  String accountRuleEarningsStep(String rate, int count);

  /// No description provided for @accountRuleFriendDiscount.
  ///
  /// In en, this message translates to:
  /// **'Friends get {discount} off Kute fees while they\'re with you.'**
  String accountRuleFriendDiscount(String discount);

  /// No description provided for @accountPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get accountPayments;

  /// No description provided for @accountYourFriends.
  ///
  /// In en, this message translates to:
  /// **'Your friends'**
  String get accountYourFriends;

  /// No description provided for @accountUserNumber.
  ///
  /// In en, this message translates to:
  /// **'User #{number}'**
  String accountUserNumber(int number);

  /// No description provided for @accountGotAFriendsCode.
  ///
  /// In en, this message translates to:
  /// **'Got a friend\'s code?'**
  String get accountGotAFriendsCode;

  /// No description provided for @accountEnterFriendCode.
  ///
  /// In en, this message translates to:
  /// **'Enter it to give your friend credit and get {discount} off Kute fees.'**
  String accountEnterFriendCode(String discount);

  /// No description provided for @accountEnterFriendCodeNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'Enter it to give your friend credit.'**
  String get accountEnterFriendCodeNoDiscount;

  /// No description provided for @accountCodeHint.
  ///
  /// In en, this message translates to:
  /// **'CODE'**
  String get accountCodeHint;

  /// No description provided for @accountApplyCode.
  ///
  /// In en, this message translates to:
  /// **'Apply code'**
  String get accountApplyCode;

  /// No description provided for @accountCodeApplied.
  ///
  /// In en, this message translates to:
  /// **'Code applied. You now get {discount} off Kute fees.'**
  String accountCodeApplied(String discount);

  /// No description provided for @accountCodeAppliedNoDiscount.
  ///
  /// In en, this message translates to:
  /// **'Code applied.'**
  String get accountCodeAppliedNoDiscount;

  /// No description provided for @accountCodeDoesntExist.
  ///
  /// In en, this message translates to:
  /// **'That code doesn\'t exist.'**
  String get accountCodeDoesntExist;

  /// No description provided for @accountFriendCodeAlreadySet.
  ///
  /// In en, this message translates to:
  /// **'You already have a friend code set.'**
  String get accountFriendCodeAlreadySet;

  /// No description provided for @accountCodeEntryClosed.
  ///
  /// In en, this message translates to:
  /// **'Code entry is closed after 7 days.'**
  String get accountCodeEntryClosed;

  /// No description provided for @accountCantUseOwnCode.
  ///
  /// In en, this message translates to:
  /// **'You can\'t use your own code.'**
  String get accountCantUseOwnCode;

  /// No description provided for @accountSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get accountSomethingWentWrong;

  /// No description provided for @accountFollowSystemTheme.
  ///
  /// In en, this message translates to:
  /// **'Follow system theme'**
  String get accountFollowSystemTheme;

  /// No description provided for @accountThemeMatchesDevice.
  ///
  /// In en, this message translates to:
  /// **'Theme matches your device'**
  String get accountThemeMatchesDevice;

  /// No description provided for @accountPreparingExport.
  ///
  /// In en, this message translates to:
  /// **'Preparing export...'**
  String get accountPreparingExport;

  /// No description provided for @accountLoadingWallet.
  ///
  /// In en, this message translates to:
  /// **'Loading {walletName}...'**
  String accountLoadingWallet(String walletName);

  /// No description provided for @accountWalletNumber.
  ///
  /// In en, this message translates to:
  /// **'Wallet {number}'**
  String accountWalletNumber(int number);

  /// No description provided for @accountSats.
  ///
  /// In en, this message translates to:
  /// **'Sats'**
  String get accountSats;

  /// No description provided for @accountCouldntReachNode.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {input}. Check the host and port, or pick a preset server.'**
  String accountCouldntReachNode(String input);

  /// No description provided for @accountWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get accountWallet;

  /// No description provided for @accountHardwareWallets.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallets'**
  String get accountHardwareWallets;

  /// No description provided for @accountWatchOnly.
  ///
  /// In en, this message translates to:
  /// **'Watch-only'**
  String get accountWatchOnly;

  /// No description provided for @accountOpenPositions.
  ///
  /// In en, this message translates to:
  /// **'Open positions'**
  String get accountOpenPositions;

  /// No description provided for @accountSpendableBalance.
  ///
  /// In en, this message translates to:
  /// **'Spendable balance'**
  String get accountSpendableBalance;

  /// No description provided for @betCouldNotLoadTopic.
  ///
  /// In en, this message translates to:
  /// **'Could not load this topic. Pull to retry.'**
  String get betCouldNotLoadTopic;

  /// No description provided for @betNoOpenMarketsInTopic.
  ///
  /// In en, this message translates to:
  /// **'No open markets in this topic right now.'**
  String get betNoOpenMarketsInTopic;

  /// No description provided for @betMinimumBetIs.
  ///
  /// In en, this message translates to:
  /// **'Minimum is {amount}.'**
  String betMinimumBetIs(String amount);

  /// No description provided for @betOrderTypeSpot.
  ///
  /// In en, this message translates to:
  /// **'Spot'**
  String get betOrderTypeSpot;

  /// No description provided for @betOrderTypeLimit.
  ///
  /// In en, this message translates to:
  /// **'Limit'**
  String get betOrderTypeLimit;

  /// No description provided for @betLimitPrice.
  ///
  /// In en, this message translates to:
  /// **'Limit price'**
  String get betLimitPrice;

  /// No description provided for @betMarketPrice.
  ///
  /// In en, this message translates to:
  /// **'Market {price}'**
  String betMarketPrice(String price);

  /// No description provided for @betLimitRestsOnBook.
  ///
  /// In en, this message translates to:
  /// **'May fill immediately at your price or better. Any unfilled shares stay in Open orders until filled or cancelled.'**
  String get betLimitRestsOnBook;

  /// No description provided for @betPlaceLimitCta.
  ///
  /// In en, this message translates to:
  /// **'Place {amount} limit at {price}'**
  String betPlaceLimitCta(String price, String amount);

  /// No description provided for @betPredictSide.
  ///
  /// In en, this message translates to:
  /// **'Place {amount} on {side}'**
  String betPredictSide(String side, String amount);

  /// No description provided for @betPredictAmount.
  ///
  /// In en, this message translates to:
  /// **'Place {amount}'**
  String betPredictAmount(String amount);

  /// No description provided for @betPredictionPlaced.
  ///
  /// In en, this message translates to:
  /// **'Prediction placed'**
  String get betPredictionPlaced;

  /// No description provided for @betCouldNotPlacePrediction.
  ///
  /// In en, this message translates to:
  /// **'Could not place prediction'**
  String get betCouldNotPlacePrediction;

  /// No description provided for @betFundsSafeRetryOrClose.
  ///
  /// In en, this message translates to:
  /// **'Your funds are safe. Retry the flow or close. Nothing is stuck.'**
  String get betFundsSafeRetryOrClose;

  /// No description provided for @betPlacingOrder.
  ///
  /// In en, this message translates to:
  /// **'Placing order'**
  String get betPlacingOrder;

  /// No description provided for @betSendingBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Sending bitcoin'**
  String get betSendingBitcoin;

  /// No description provided for @betContactingPolymarket.
  ///
  /// In en, this message translates to:
  /// **'Contacting Polymarket'**
  String get betContactingPolymarket;

  /// No description provided for @betSwitchToSpendingWallet.
  ///
  /// In en, this message translates to:
  /// **'Switch to your spending wallet'**
  String get betSwitchToSpendingWallet;

  /// No description provided for @betAddSpendingWallet.
  ///
  /// In en, this message translates to:
  /// **'Add a spending wallet'**
  String get betAddSpendingWallet;

  /// No description provided for @betSigningOnlyCantPlaceOrders.
  ///
  /// In en, this message translates to:
  /// **'Predictions are placed from your spending wallet. Your current account is signing-only and can\'t place orders.'**
  String get betSigningOnlyCantPlaceOrders;

  /// No description provided for @betNeedSpendingWallet.
  ///
  /// In en, this message translates to:
  /// **'You need a spending wallet to place predictions. Hardware, watch-only and tracked accounts can\'t sign orders.'**
  String get betNeedSpendingWallet;

  /// No description provided for @betSwitchWallet.
  ///
  /// In en, this message translates to:
  /// **'Switch wallet'**
  String get betSwitchWallet;

  /// No description provided for @betCreateSpendingWallet.
  ///
  /// In en, this message translates to:
  /// **'Create spending wallet'**
  String get betCreateSpendingWallet;

  /// No description provided for @betYesPrice.
  ///
  /// In en, this message translates to:
  /// **'Yes {price}'**
  String betYesPrice(String price);

  /// No description provided for @betNoPrice.
  ///
  /// In en, this message translates to:
  /// **'No {price}'**
  String betNoPrice(String price);

  /// No description provided for @betPlacingOrderEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Placing order...'**
  String get betPlacingOrderEllipsis;

  /// No description provided for @betCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current value'**
  String get betCurrentValue;

  /// No description provided for @betPercentChance.
  ///
  /// In en, this message translates to:
  /// **'{percent}% chance'**
  String betPercentChance(String percent);

  /// No description provided for @betShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get betShares;

  /// No description provided for @betInvested.
  ///
  /// In en, this message translates to:
  /// **'Invested'**
  String get betInvested;

  /// No description provided for @betEndsDate.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String betEndsDate(String date);

  /// No description provided for @betNoHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get betNoHistoryYet;

  /// No description provided for @betClosingConditions.
  ///
  /// In en, this message translates to:
  /// **'Closing Conditions'**
  String get betClosingConditions;

  /// No description provided for @betMarketCategory.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get betMarketCategory;

  /// No description provided for @betLiveUpper.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get betLiveUpper;

  /// No description provided for @betVersus.
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get betVersus;

  /// No description provided for @betEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Ends in'**
  String get betEndsIn;

  /// No description provided for @betYesChance.
  ///
  /// In en, this message translates to:
  /// **'Yes chance'**
  String get betYesChance;

  /// No description provided for @betAwaitingLiquidity.
  ///
  /// In en, this message translates to:
  /// **'Not open yet'**
  String get betAwaitingLiquidity;

  /// No description provided for @betNoPricesYet.
  ///
  /// In en, this message translates to:
  /// **'No prices yet'**
  String get betNoPricesYet;

  /// No description provided for @betTapMarketToPredict.
  ///
  /// In en, this message translates to:
  /// **'Tap a market to predict'**
  String get betTapMarketToPredict;

  /// No description provided for @betMarketsSuffix.
  ///
  /// In en, this message translates to:
  /// **'markets'**
  String get betMarketsSuffix;

  /// No description provided for @betNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get betNo;

  /// No description provided for @betDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get betDraw;

  /// No description provided for @bet24hVolume.
  ///
  /// In en, this message translates to:
  /// **'24h Volume'**
  String get bet24hVolume;

  /// No description provided for @betTotalVolume.
  ///
  /// In en, this message translates to:
  /// **'Total volume'**
  String get betTotalVolume;

  /// No description provided for @betLiquidity.
  ///
  /// In en, this message translates to:
  /// **'Liquidity'**
  String get betLiquidity;

  /// No description provided for @betMarketInfo.
  ///
  /// In en, this message translates to:
  /// **'Market info'**
  String get betMarketInfo;

  /// No description provided for @betLivestream.
  ///
  /// In en, this message translates to:
  /// **'Livestream'**
  String get betLivestream;

  /// No description provided for @betAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get betAbout;

  /// No description provided for @betResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get betResolution;

  /// No description provided for @betMarketCreated.
  ///
  /// In en, this message translates to:
  /// **'Market created'**
  String get betMarketCreated;

  /// No description provided for @betTradingIsOpen.
  ///
  /// In en, this message translates to:
  /// **'Trading is open'**
  String get betTradingIsOpen;

  /// No description provided for @betTradingActive.
  ///
  /// In en, this message translates to:
  /// **'Trading active'**
  String get betTradingActive;

  /// No description provided for @betBuyAndSellShares.
  ///
  /// In en, this message translates to:
  /// **'Buy and sell shares'**
  String get betBuyAndSellShares;

  /// No description provided for @betMarketCloses.
  ///
  /// In en, this message translates to:
  /// **'Market closes'**
  String get betMarketCloses;

  /// No description provided for @betDateTbd.
  ///
  /// In en, this message translates to:
  /// **'Date TBD'**
  String get betDateTbd;

  /// No description provided for @betWinnersPaid.
  ///
  /// In en, this message translates to:
  /// **'Winners paid \$1.00 per share'**
  String get betWinnersPaid;

  /// No description provided for @betGroupMoneyline.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get betGroupMoneyline;

  /// No description provided for @betGroupSpread.
  ///
  /// In en, this message translates to:
  /// **'Handicap'**
  String get betGroupSpread;

  /// No description provided for @betGroupTotals.
  ///
  /// In en, this message translates to:
  /// **'Over-Under'**
  String get betGroupTotals;

  /// No description provided for @betGroupProps.
  ///
  /// In en, this message translates to:
  /// **'Other predictions'**
  String get betGroupProps;

  /// No description provided for @betGroupOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get betGroupOther;

  /// No description provided for @betLimitSellPlaced.
  ///
  /// In en, this message translates to:
  /// **'Limit sell submitted at {price}. Track any unfilled shares in Open orders.'**
  String betLimitSellPlaced(String price);

  /// No description provided for @betPositionSold.
  ///
  /// In en, this message translates to:
  /// **'Position sold'**
  String get betPositionSold;

  /// No description provided for @betCouldNotSell.
  ///
  /// In en, this message translates to:
  /// **'Could not sell'**
  String get betCouldNotSell;

  /// No description provided for @betSharesSafeRetryOrClose.
  ///
  /// In en, this message translates to:
  /// **'Your shares are safe. Retry, or close. Nothing is stuck.'**
  String get betSharesSafeRetryOrClose;

  /// No description provided for @betSellAt.
  ///
  /// In en, this message translates to:
  /// **'Sell at'**
  String get betSellAt;

  /// No description provided for @betSharesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shares'**
  String betSharesCount(String count);

  /// No description provided for @betAvgNowPrice.
  ///
  /// In en, this message translates to:
  /// **'Avg {avg}  ·  Now {now}'**
  String betAvgNowPrice(String avg, String now);

  /// No description provided for @betSellingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Selling...'**
  String get betSellingEllipsis;

  /// No description provided for @betPlaceLimitAtPrice.
  ///
  /// In en, this message translates to:
  /// **'Sell at {price} · limit'**
  String betPlaceLimitAtPrice(String price);

  /// No description provided for @betPlaceLimit.
  ///
  /// In en, this message translates to:
  /// **'Set a limit price'**
  String get betPlaceLimit;

  /// No description provided for @sellNow.
  ///
  /// In en, this message translates to:
  /// **'Sell now'**
  String get sellNow;

  /// No description provided for @betPositionCleared.
  ///
  /// In en, this message translates to:
  /// **'Position cleared'**
  String get betPositionCleared;

  /// No description provided for @predictDustSellError.
  ///
  /// In en, this message translates to:
  /// **'No one is buying this outcome anymore. It\'s trading at effectively \$0, so these shares can\'t be sold. Once the market resolves you can clear the position.'**
  String get predictDustSellError;

  /// No description provided for @betAlreadyClaimedRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Already claimed. Refreshing…'**
  String get betAlreadyClaimedRefreshing;

  /// Shown when a claim is tapped on a prediction whose shares are no longer in the account (sold, or claimed already), so nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Already sold or claimed. Nothing is left to claim on this prediction.'**
  String get betClaimNothingHeld;

  /// Shown when a claim is tapped before the market's result is reported on chain, so nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Polymarket is still recording this result. Your {amount} will be ready to claim in a few minutes.'**
  String betClaimResultRecording(String amount);

  /// No description provided for @betNoPayout.
  ///
  /// In en, this message translates to:
  /// **'No payout'**
  String get betNoPayout;

  /// No description provided for @betClaimAmount.
  ///
  /// In en, this message translates to:
  /// **'Claim {amount}'**
  String betClaimAmount(String amount);

  /// No description provided for @betClearPosition.
  ///
  /// In en, this message translates to:
  /// **'Clear position'**
  String get betClearPosition;

  /// No description provided for @betOpenOrders.
  ///
  /// In en, this message translates to:
  /// **'Open orders'**
  String get betOpenOrders;

  /// No description provided for @betLoadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get betLoadingEllipsis;

  /// No description provided for @betNoRestingOrders.
  ///
  /// In en, this message translates to:
  /// **'No resting orders.\nLimit orders you place show up here.'**
  String get betNoRestingOrders;

  /// No description provided for @betCouldNotCancel.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel. Try again.'**
  String get betCouldNotCancel;

  /// No description provided for @betBuyUpper.
  ///
  /// In en, this message translates to:
  /// **'BUY'**
  String get betBuyUpper;

  /// No description provided for @betSellUpper.
  ///
  /// In en, this message translates to:
  /// **'SELL'**
  String get betSellUpper;

  /// No description provided for @betOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get betOrder;

  /// No description provided for @betLimitPending.
  ///
  /// In en, this message translates to:
  /// **'Limit · pending'**
  String get betLimitPending;

  /// No description provided for @betExecutesAt.
  ///
  /// In en, this message translates to:
  /// **'Executes at {price}'**
  String betExecutesAt(String price);

  /// No description provided for @betBuysWhenPriceDrops.
  ///
  /// In en, this message translates to:
  /// **'Buys when the price drops to {price}'**
  String betBuysWhenPriceDrops(String price);

  /// No description provided for @betBuysWhenPriceReaches.
  ///
  /// In en, this message translates to:
  /// **'Buys when the price reaches {price}'**
  String betBuysWhenPriceReaches(String price);

  /// No description provided for @betSellsWhenPriceRises.
  ///
  /// In en, this message translates to:
  /// **'Sells when the price rises to {price}'**
  String betSellsWhenPriceRises(String price);

  /// No description provided for @betSellsWhenPriceReaches.
  ///
  /// In en, this message translates to:
  /// **'Sells when the price reaches {price}'**
  String betSellsWhenPriceReaches(String price);

  /// No description provided for @betBuySharesCost.
  ///
  /// In en, this message translates to:
  /// **'Buy {count} shares · {cost}'**
  String betBuySharesCost(String count, String cost);

  /// No description provided for @betSellSharesCost.
  ///
  /// In en, this message translates to:
  /// **'Sell {count} shares · {cost}'**
  String betSellSharesCost(String count, String cost);

  /// No description provided for @betPercentFilled.
  ///
  /// In en, this message translates to:
  /// **'{percent}% filled, partially matched'**
  String betPercentFilled(String percent);

  /// No description provided for @betRestingBuyNote.
  ///
  /// In en, this message translates to:
  /// **'Resting on the book. It won\'t show in your positions until it fills.'**
  String get betRestingBuyNote;

  /// No description provided for @betRestingSellNote.
  ///
  /// In en, this message translates to:
  /// **'Resting on the book. Your shares stay held until it fills.'**
  String get betRestingSellNote;

  /// No description provided for @betRoutingToBitcoinWallet.
  ///
  /// In en, this message translates to:
  /// **'Routing to your Bitcoin wallet…'**
  String get betRoutingToBitcoinWallet;

  /// No description provided for @betEndsCountdown.
  ///
  /// In en, this message translates to:
  /// **'ENDS {time}'**
  String betEndsCountdown(String time);

  /// No description provided for @depositToPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Deposit to'**
  String get depositToPickerTitle;

  /// No description provided for @depositPickHowYouWantToPay.
  ///
  /// In en, this message translates to:
  /// **'Pick how you want to pay.'**
  String get depositPickHowYouWantToPay;

  /// No description provided for @homeNavConversionStarted.
  ///
  /// In en, this message translates to:
  /// **'Conversion started'**
  String get homeNavConversionStarted;

  /// No description provided for @sendBitcoinLightningOrSparkAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin, Lightning or Spark address'**
  String get sendBitcoinLightningOrSparkAddressHint;

  /// No description provided for @sendAutoSwapFromBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Auto-swap from Bitcoin'**
  String get sendAutoSwapFromBitcoin;

  /// No description provided for @sendAddressNotIdentified.
  ///
  /// In en, this message translates to:
  /// **'Address not identified'**
  String get sendAddressNotIdentified;

  /// No description provided for @sendChooseANetworkFromTheSheetToContinue.
  ///
  /// In en, this message translates to:
  /// **'Choose a network from the sheet to continue'**
  String get sendChooseANetworkFromTheSheetToContinue;

  /// No description provided for @sendOtherCrypto.
  ///
  /// In en, this message translates to:
  /// **'Other crypto'**
  String get sendOtherCrypto;

  /// No description provided for @sendFeeTimeTotal.
  ///
  /// In en, this message translates to:
  /// **'{time}  ·  ₿{total}'**
  String sendFeeTimeTotal(String time, String total);

  /// No description provided for @sendWhereShouldTheMoneyLand.
  ///
  /// In en, this message translates to:
  /// **'Where should the money land?'**
  String get sendWhereShouldTheMoneyLand;

  /// No description provided for @sendWalletChangedMidPrepare.
  ///
  /// In en, this message translates to:
  /// **'Wallet changed mid-prepare. Tap Try again to rebuild against the current wallet.'**
  String get sendWalletChangedMidPrepare;

  /// No description provided for @sendAmountBelowNetworkMinimumOnChain.
  ///
  /// In en, this message translates to:
  /// **'This amount is below the network\'s minimum for an on-chain transaction. Try a larger amount or pick a lower fee.'**
  String get sendAmountBelowNetworkMinimumOnChain;

  /// No description provided for @sendNotEnoughBalanceCoverFee.
  ///
  /// In en, this message translates to:
  /// **'Not enough balance to cover the amount plus the network fee. Lower the amount, or tap 100% to send everything.'**
  String get sendNotEnoughBalanceCoverFee;

  /// No description provided for @sendFeeChangedTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The network fee changed since you reviewed. Nothing left your wallet. Try again to see the new amount.'**
  String get sendFeeChangedTryAgain;

  /// No description provided for @sendTheDestinationAddressIsInvalid.
  ///
  /// In en, this message translates to:
  /// **'The destination address is invalid.'**
  String get sendTheDestinationAddressIsInvalid;

  /// No description provided for @sendWalletCantSignLightningDestinationPicker.
  ///
  /// In en, this message translates to:
  /// **'This wallet sends on-chain Bitcoin. Switch to your spending wallet to pay Lightning.'**
  String get sendWalletCantSignLightningDestinationPicker;

  /// No description provided for @sendFromPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Send from'**
  String get sendFromPickerTitle;

  /// No description provided for @sendHowMuchBitcoin.
  ///
  /// In en, this message translates to:
  /// **'How much Bitcoin?'**
  String get sendHowMuchBitcoin;

  /// No description provided for @sendHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much?'**
  String get sendHowMuch;

  /// No description provided for @sendWhereShouldItLand.
  ///
  /// In en, this message translates to:
  /// **'Where should it land?'**
  String get sendWhereShouldItLand;

  /// No description provided for @sendReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get sendReview;

  /// No description provided for @sendConfirmTheDetails.
  ///
  /// In en, this message translates to:
  /// **'Confirm the details.'**
  String get sendConfirmTheDetails;

  /// No description provided for @sendSign.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get sendSign;

  /// No description provided for @sendSignTheTransactionOnYourDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign the transaction on your device.'**
  String get sendSignTheTransactionOnYourDevice;

  /// No description provided for @sendAmountUnitAvailableWithFiat.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit} available · {fiat}'**
  String sendAmountUnitAvailableWithFiat(
      String amount, String unit, String fiat);

  /// No description provided for @sendCalculatingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get sendCalculatingEllipsis;

  /// No description provided for @sendLiveQuoteProvider.
  ///
  /// In en, this message translates to:
  /// **'Live quote · {provider}'**
  String sendLiveQuoteProvider(String provider);

  /// No description provided for @sendLiveQuoteProviderWithFee.
  ///
  /// In en, this message translates to:
  /// **'Live quote · {provider} · {fee} fee'**
  String sendLiveQuoteProviderWithFee(String provider, String fee);

  /// No description provided for @sendAvailableBalanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Available · {balance}'**
  String sendAvailableBalanceSubtitle(String balance);

  /// No description provided for @sendEstimatedTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get sendEstimatedTime;

  /// No description provided for @sendNetworkSpeed.
  ///
  /// In en, this message translates to:
  /// **'Network speed'**
  String get sendNetworkSpeed;

  /// No description provided for @sendNeedHaveBalance.
  ///
  /// In en, this message translates to:
  /// **'Need ₿{needed} · have ₿{available}'**
  String sendNeedHaveBalance(String needed, String available);

  /// No description provided for @sendAmountTooSmallForOnChainSend.
  ///
  /// In en, this message translates to:
  /// **'Amount too small for an on-chain send. Increase the amount.'**
  String get sendAmountTooSmallForOnChainSend;

  /// No description provided for @sendAmountBelowNetworkMinimum.
  ///
  /// In en, this message translates to:
  /// **'Amount is below the network minimum. Increase the amount.'**
  String get sendAmountBelowNetworkMinimum;

  /// No description provided for @sendDestinationAddressIsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Destination address is invalid.'**
  String get sendDestinationAddressIsInvalid;

  /// No description provided for @sendFeeSatsWithFiat.
  ///
  /// In en, this message translates to:
  /// **'{sats} sats · {fiat}'**
  String sendFeeSatsWithFiat(String sats, String fiat);

  /// No description provided for @sendRoutingFee.
  ///
  /// In en, this message translates to:
  /// **'Routing fee'**
  String get sendRoutingFee;

  /// No description provided for @sendPaymentRequestOnlySupportsLightning.
  ///
  /// In en, this message translates to:
  /// **'This payment request only supports Lightning. Switch to a Lightning-capable wallet to pay.'**
  String get sendPaymentRequestOnlySupportsLightning;

  /// No description provided for @sendAssetOnNetworkAddressHint.
  ///
  /// In en, this message translates to:
  /// **'{asset} on {network} address'**
  String sendAssetOnNetworkAddressHint(String asset, String network);

  /// No description provided for @sendPasteBitcoinAddress.
  ///
  /// In en, this message translates to:
  /// **'Paste Bitcoin address'**
  String get sendPasteBitcoinAddress;

  /// No description provided for @sendPasteAddressOrLightning.
  ///
  /// In en, this message translates to:
  /// **'Paste address or @lightning'**
  String get sendPasteAddressOrLightning;

  /// No description provided for @sendWalletCantSignLightningOtherNetwork.
  ///
  /// In en, this message translates to:
  /// **'This wallet sends on-chain Bitcoin. Switch to your spending wallet to pay Lightning.'**
  String get sendWalletCantSignLightningOtherNetwork;

  /// No description provided for @sendSendingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sendSendingEllipsis;

  /// No description provided for @sendFundsLeaveYourWalletImmediately.
  ///
  /// In en, this message translates to:
  /// **'Funds leave your wallet immediately'**
  String get sendFundsLeaveYourWalletImmediately;

  /// No description provided for @sendBuildingUnsignedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Building unsigned transaction…'**
  String get sendBuildingUnsignedTransaction;

  /// No description provided for @sendCouldntPrepareTheTransaction.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare the transaction'**
  String get sendCouldntPrepareTheTransaction;

  /// No description provided for @sendUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get sendUnknownError;

  /// No description provided for @sendSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get sendSendFailed;

  /// No description provided for @sendReadyToSend.
  ///
  /// In en, this message translates to:
  /// **'Ready to send'**
  String get sendReadyToSend;

  /// No description provided for @sendSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get sendSteps;

  /// No description provided for @sendProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get sendProgress;

  /// No description provided for @sendDontCloseTheAppWhileThisFinishes.
  ///
  /// In en, this message translates to:
  /// **'Don\'t close the app while this finishes.'**
  String get sendDontCloseTheAppWhileThisFinishes;

  /// No description provided for @activityTracked.
  ///
  /// In en, this message translates to:
  /// **'Tracked'**
  String get activityTracked;

  /// No description provided for @activitySignerDevices.
  ///
  /// In en, this message translates to:
  /// **'Signer devices'**
  String get activitySignerDevices;

  /// No description provided for @activityNoAccountsMatchAction.
  ///
  /// In en, this message translates to:
  /// **'No accounts match this action.'**
  String get activityNoAccountsMatchAction;

  /// No description provided for @activityUtxos.
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get activityUtxos;

  /// No description provided for @activityBitcoinWaiting.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin waiting'**
  String get activityBitcoinWaiting;

  /// No description provided for @activityTapToAddToWallet.
  ///
  /// In en, this message translates to:
  /// **'Tap to add to wallet'**
  String get activityTapToAddToWallet;

  /// No description provided for @activityAddToWallet.
  ///
  /// In en, this message translates to:
  /// **'Add to wallet'**
  String get activityAddToWallet;

  /// No description provided for @activityArriving.
  ///
  /// In en, this message translates to:
  /// **'Arriving'**
  String get activityArriving;

  /// No description provided for @activityConfirmationsOfThree.
  ///
  /// In en, this message translates to:
  /// **'{current} of 3 confirmations'**
  String activityConfirmationsOfThree(String current);

  /// No description provided for @activityReadyAfterConfirmations.
  ///
  /// In en, this message translates to:
  /// **'{current} of 3 confirmations. Your bitcoin is ready to use by the third, often sooner.'**
  String activityReadyAfterConfirmations(String current);

  /// No description provided for @activityFeeLimit.
  ///
  /// In en, this message translates to:
  /// **'Fee limit'**
  String get activityFeeLimit;

  /// No description provided for @activityUpToAmount.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount}'**
  String activityUpToAmount(String amount);

  /// No description provided for @activityFeeQuotedWhenAdded.
  ///
  /// In en, this message translates to:
  /// **'Quoted when you add it'**
  String get activityFeeQuotedWhenAdded;

  /// No description provided for @activityBitcoinAdded.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin added to your wallet'**
  String get activityBitcoinAdded;

  /// No description provided for @activityBitcoinAddedPending.
  ///
  /// In en, this message translates to:
  /// **'It can take a few minutes to show in your balance.'**
  String get activityBitcoinAddedPending;

  /// No description provided for @activityRefundStarted.
  ///
  /// In en, this message translates to:
  /// **'Refund started'**
  String get activityRefundStarted;

  /// No description provided for @depositAddFeeAboveLimit.
  ///
  /// In en, this message translates to:
  /// **'Adding this bitcoin needs a network fee of {amount}, above your limit. Raise the limit under Advanced and try again.'**
  String depositAddFeeAboveLimit(String amount);

  /// No description provided for @receiveMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get receiveMoreOptions;

  /// No description provided for @investingTrailingStop.
  ///
  /// In en, this message translates to:
  /// **'Trailing stop'**
  String get investingTrailingStop;

  /// No description provided for @receiveCreateRequest.
  ///
  /// In en, this message translates to:
  /// **'Create request'**
  String get receiveCreateRequest;

  /// No description provided for @receiveSendUsdcOnPolygonAutoConvert.
  ///
  /// In en, this message translates to:
  /// **'Send USDC on Polygon. It converts to bitcoin once it lands.'**
  String get receiveSendUsdcOnPolygonAutoConvert;

  /// No description provided for @receiveSendUsdcOnPolygon.
  ///
  /// In en, this message translates to:
  /// **'Send USDC on Polygon.'**
  String get receiveSendUsdcOnPolygon;

  /// No description provided for @receiveBridgedUsdcAccepted.
  ///
  /// In en, this message translates to:
  /// **'Bridged USDC (USDC.e) is also accepted.'**
  String get receiveBridgedUsdcAccepted;

  /// No description provided for @activityChangeOutput.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get activityChangeOutput;

  /// No description provided for @activityNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get activityNetworkFee;

  /// No description provided for @activityOtherOutputs.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get activityOtherOutputs;

  /// No description provided for @activityNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get activityNeedsAttention;

  /// No description provided for @activityStatusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get activityStatusCode;

  /// No description provided for @activityNoLongerTracked.
  ///
  /// In en, this message translates to:
  /// **'No longer tracked'**
  String get activityNoLongerTracked;

  /// No description provided for @activityLegacyOrderNote.
  ///
  /// In en, this message translates to:
  /// **'Kute no longer supports this provider, so this order is not updated. The details show the last status Kute saw.'**
  String get activityLegacyOrderNote;

  /// No description provided for @activityTrackExchange.
  ///
  /// In en, this message translates to:
  /// **'Track this exchange'**
  String get activityTrackExchange;

  /// No description provided for @activityViewOnBlockchain.
  ///
  /// In en, this message translates to:
  /// **'View on the blockchain'**
  String get activityViewOnBlockchain;

  /// No description provided for @searchIdlePrompt.
  ///
  /// In en, this message translates to:
  /// **'Search transactions, Predictions and Investing'**
  String get searchIdlePrompt;

  /// No description provided for @searchInvestingMarket.
  ///
  /// In en, this message translates to:
  /// **'Investing market'**
  String get searchInvestingMarket;

  /// No description provided for @searchCryptoMarkets.
  ///
  /// In en, this message translates to:
  /// **'Crypto markets'**
  String get searchCryptoMarkets;

  /// No description provided for @activitySender.
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get activitySender;

  /// No description provided for @depositAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add this bitcoin to your wallet. Try again.'**
  String get depositAddFailed;

  /// No description provided for @depositRefundStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the refund. Try again.'**
  String get depositRefundStartFailed;

  /// No description provided for @receiveRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the payment request. Try again.'**
  String get receiveRequestFailed;

  /// No description provided for @receiveDepositAddressFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create a deposit address. Try again.'**
  String get receiveDepositAddressFailed;

  /// Shown when a cross-chain receive is attempted into a wallet that cannot be delivered to, which is any wallet other than the Spark spending one.
  ///
  /// In en, this message translates to:
  /// **'Other coins can only arrive in your spending wallet. Switch to it and try again.'**
  String get receiveOtherCoinsSpendingOnly;

  /// Shown when the provider refuses to create a reusable deposit address for the picked coin and network. It is about the pair, not about the wallet, so it must never be confused with receiveOtherCoinsSpendingOnly.
  ///
  /// In en, this message translates to:
  /// **'This coin and network are not available for deposits yet. Pick another one.'**
  String get receiveCoinNetworkUnavailable;

  /// Shown when a cross-chain receive is attempted into the Predictions balance, which settles at an address the conversion cannot pay.
  ///
  /// In en, this message translates to:
  /// **'Other coins cannot arrive in Predictions. Receive them in your spending wallet, then move them across.'**
  String get receiveOtherCoinsNotToPredictions;

  /// No description provided for @activityStables.
  ///
  /// In en, this message translates to:
  /// **'Stables'**
  String get activityStables;

  /// No description provided for @activityBitcoinWallet.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin wallet'**
  String get activityBitcoinWallet;

  /// No description provided for @activityNoBalancesYet.
  ///
  /// In en, this message translates to:
  /// **'No balances yet'**
  String get activityNoBalancesYet;

  /// No description provided for @activityUtxoCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 coin} other{{count} coins}}'**
  String activityUtxoCountLabel(int count);

  /// No description provided for @activityLiveLine.
  ///
  /// In en, this message translates to:
  /// **'live line'**
  String get activityLiveLine;

  /// No description provided for @activityToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get activityToday;

  /// No description provided for @activityYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get activityYesterday;

  /// Activity row title for a purchase: Bitcoin bought with a card or bank, or an Investing spot token bought. name is the asset.
  ///
  /// In en, this message translates to:
  /// **'Bought · {name}'**
  String activityRowBought(String name);

  /// Activity row title for a sale: a prediction sold before the result (name is the outcome or a short market label), Bitcoin or an Investing spot token sold. Never says the market's result.
  ///
  /// In en, this message translates to:
  /// **'Sold · {name}'**
  String activityRowSold(String name);

  /// Activity row title for a prediction that paid out. name is the outcome predicted.
  ///
  /// In en, this message translates to:
  /// **'Won · {name}'**
  String activityRowWon(String name);

  /// Activity row title for a prediction that settled with no payout. name is the outcome predicted.
  ///
  /// In en, this message translates to:
  /// **'Lost · {name}'**
  String activityRowLost(String name);

  /// Activity row title for a prediction the person made (a purchase of outcome shares). name is the outcome. Never 'bet'.
  ///
  /// In en, this message translates to:
  /// **'Prediction · {name}'**
  String activityRowPrediction(String name);

  /// Activity row title for an Investing fill that opened or added to a long position. coin is the symbol.
  ///
  /// In en, this message translates to:
  /// **'Long {coin}'**
  String activityRowLong(String coin);

  /// Activity row title for an Investing fill that opened or added to a short position. coin is the symbol.
  ///
  /// In en, this message translates to:
  /// **'Short {coin}'**
  String activityRowShort(String coin);

  /// Activity row title for an Investing fill that closed a position fully. coin is the symbol.
  ///
  /// In en, this message translates to:
  /// **'Closed {coin}'**
  String activityRowClosed(String coin);

  /// Activity row title for an Investing fill that made a position smaller without closing it. coin is the symbol.
  ///
  /// In en, this message translates to:
  /// **'Reduced {coin}'**
  String activityRowReduced(String coin);

  /// Activity row title for an Investing position the venue liquidated. coin is the symbol.
  ///
  /// In en, this message translates to:
  /// **'Liquidated {coin}'**
  String activityRowLiquidated(String coin);

  /// Context line under a Deposit or conversion row: where the money went (Predictions, Investing, Dollars, Bitcoin). Lowercase, followed by the time.
  ///
  /// In en, this message translates to:
  /// **'to {name}'**
  String activityRowTo(String name);

  /// Context line under a Withdraw row: the balance the money left (Predictions, Investing, Dollars). Lowercase, followed by the time.
  ///
  /// In en, this message translates to:
  /// **'from {name}'**
  String activityRowFrom(String name);

  /// Activity row title for money moved into one of the person's balances (Predictions, Investing, Dollars). A noun, short.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get activityRowDeposit;

  /// Activity row title for money moved out of one of the person's balances (Predictions, Investing, Dollars). Short.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get activityRowWithdraw;

  /// No description provided for @activityNoTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get activityNoTransactionsYet;

  /// No description provided for @activityDollar.
  ///
  /// In en, this message translates to:
  /// **'Dollar'**
  String get activityDollar;

  /// No description provided for @activityBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get activityBlock;

  /// No description provided for @activityTxHash.
  ///
  /// In en, this message translates to:
  /// **'Tx Hash'**
  String get activityTxHash;

  /// No description provided for @activityOnChain.
  ///
  /// In en, this message translates to:
  /// **'On-chain'**
  String get activityOnChain;

  /// No description provided for @activityAwaitingDeposit.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Deposit'**
  String get activityAwaitingDeposit;

  /// No description provided for @activityDepositReceived.
  ///
  /// In en, this message translates to:
  /// **'Deposit Received'**
  String get activityDepositReceived;

  /// No description provided for @activityApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get activityApproved;

  /// No description provided for @activityProcessingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get activityProcessingEllipsis;

  /// No description provided for @usdAccountTab.
  ///
  /// In en, this message translates to:
  /// **'Dollars'**
  String get usdAccountTab;

  /// No description provided for @activityFromAmount.
  ///
  /// In en, this message translates to:
  /// **'from {amount}'**
  String activityFromAmount(String amount);

  /// No description provided for @activityUnclaimed.
  ///
  /// In en, this message translates to:
  /// **'Unclaimed'**
  String get activityUnclaimed;

  /// No description provided for @activitySwapLegs.
  ///
  /// In en, this message translates to:
  /// **'Swap · {from} → {to}'**
  String activitySwapLegs(String from, String to);

  /// No description provided for @activityYourWallet.
  ///
  /// In en, this message translates to:
  /// **'Your wallet'**
  String get activityYourWallet;

  /// No description provided for @activityReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get activityReference;

  /// No description provided for @activityDepositNetwork.
  ///
  /// In en, this message translates to:
  /// **'Deposit Network'**
  String get activityDepositNetwork;

  /// No description provided for @activityReceiveNetwork.
  ///
  /// In en, this message translates to:
  /// **'Receive Network'**
  String get activityReceiveNetwork;

  /// No description provided for @activityWithdrawalAddress.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal Address'**
  String get activityWithdrawalAddress;

  /// No description provided for @activityExchangeId.
  ///
  /// In en, this message translates to:
  /// **'Exchange ID'**
  String get activityExchangeId;

  /// No description provided for @activityInvoicePaidByCashApp.
  ///
  /// In en, this message translates to:
  /// **'Invoice paid by Cash App'**
  String get activityInvoicePaidByCashApp;

  /// No description provided for @activityDeliveredTo.
  ///
  /// In en, this message translates to:
  /// **'Delivered to'**
  String get activityDeliveredTo;

  /// No description provided for @activityRefundAddress.
  ///
  /// In en, this message translates to:
  /// **'Refund Address'**
  String get activityRefundAddress;

  /// No description provided for @predictionsCryptoMarkets.
  ///
  /// In en, this message translates to:
  /// **'Crypto markets'**
  String get predictionsCryptoMarkets;

  /// No description provided for @activitySettling.
  ///
  /// In en, this message translates to:
  /// **'Settling'**
  String get activitySettling;

  /// No description provided for @activitySettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get activitySettled;

  /// No description provided for @activityAmountProfit.
  ///
  /// In en, this message translates to:
  /// **'{amount} profit'**
  String activityAmountProfit(String amount);

  /// No description provided for @activityAmountLoss.
  ///
  /// In en, this message translates to:
  /// **'{amount} loss'**
  String activityAmountLoss(String amount);

  /// No description provided for @activitySharesLowercase.
  ///
  /// In en, this message translates to:
  /// **'shares'**
  String get activitySharesLowercase;

  /// No description provided for @activityTrade.
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get activityTrade;

  /// No description provided for @activityOutcome.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get activityOutcome;

  /// No description provided for @activityBacked.
  ///
  /// In en, this message translates to:
  /// **'Predicted'**
  String get activityBacked;

  /// No description provided for @activityProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get activityProfit;

  /// No description provided for @activityLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get activityLoss;

  /// No description provided for @activityValueThen.
  ///
  /// In en, this message translates to:
  /// **'Value then'**
  String get activityValueThen;

  /// No description provided for @activityChangeSince.
  ///
  /// In en, this message translates to:
  /// **'Change since'**
  String get activityChangeSince;

  /// No description provided for @activityNerdData.
  ///
  /// In en, this message translates to:
  /// **'Nerd data'**
  String get activityNerdData;

  /// No description provided for @activityInputIndex.
  ///
  /// In en, this message translates to:
  /// **'Input #{index}'**
  String activityInputIndex(String index);

  /// No description provided for @activityOutputIndex.
  ///
  /// In en, this message translates to:
  /// **'Output #{index}'**
  String activityOutputIndex(String index);

  /// No description provided for @activityOnChainDeposit.
  ///
  /// In en, this message translates to:
  /// **'On-Chain Deposit'**
  String get activityOnChainDeposit;

  /// No description provided for @predictOrderBookUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Order book unavailable'**
  String get predictOrderBookUnavailable;

  /// No description provided for @predictTradeYes.
  ///
  /// In en, this message translates to:
  /// **'Trade Yes {price}'**
  String predictTradeYes(String price);

  /// No description provided for @predictTradeNo.
  ///
  /// In en, this message translates to:
  /// **'Trade No {price}'**
  String predictTradeNo(String price);

  /// No description provided for @predictInfoTab.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get predictInfoTab;

  /// No description provided for @predictNewsTab.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get predictNewsTab;

  /// No description provided for @predictEndDate.
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get predictEndDate;

  /// No description provided for @predictTbd.
  ///
  /// In en, this message translates to:
  /// **'TBD'**
  String get predictTbd;

  /// No description provided for @predictPayoutPerShare.
  ///
  /// In en, this message translates to:
  /// **'\$1.00 / share'**
  String get predictPayoutPerShare;

  /// No description provided for @predictJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get predictJustNow;

  /// No description provided for @predictMinutesAgoShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String predictMinutesAgoShort(String minutes);

  /// No description provided for @predictHoursAgoShort.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String predictHoursAgoShort(String hours);

  /// No description provided for @predictDaysAgoShort.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String predictDaysAgoShort(String days);

  /// No description provided for @predictNoCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get predictNoCommentsYet;

  /// No description provided for @predictAnonymousUser.
  ///
  /// In en, this message translates to:
  /// **'Anon'**
  String get predictAnonymousUser;

  /// No description provided for @betPlacedJustNow.
  ///
  /// In en, this message translates to:
  /// **'placed just now'**
  String get betPlacedJustNow;

  /// No description provided for @betPlacedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'placed {minutes}m ago'**
  String betPlacedMinutesAgo(int minutes);

  /// No description provided for @betPlacedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'placed {hours}h ago'**
  String betPlacedHoursAgo(int hours);

  /// No description provided for @betPlacedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'placed {days}d ago'**
  String betPlacedDaysAgo(int days);

  /// Tag on the Predictions chart's dashed line at the user's average price; the price follows it, e.g. Bought · 32¢.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get polyChartBought;

  /// Predictions chart summary: the change over the visible span, e.g. +2.1% past 4d.
  ///
  /// In en, this message translates to:
  /// **'{change} past {span}'**
  String polyChartChangePast(String change, String span);

  /// No description provided for @betTbd.
  ///
  /// In en, this message translates to:
  /// **'TBD'**
  String get betTbd;

  /// No description provided for @betClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get betClosed;

  /// No description provided for @betNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get betNow;

  /// No description provided for @homeNavPredictionsWalletNotReadyYet.
  ///
  /// In en, this message translates to:
  /// **'Predictions wallet not ready yet. Try again in a moment.'**
  String get homeNavPredictionsWalletNotReadyYet;

  /// No description provided for @homeNavPredictionsBalance.
  ///
  /// In en, this message translates to:
  /// **'Predictions balance'**
  String get homeNavPredictionsBalance;

  /// No description provided for @homeNavMasterFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Master fingerprint'**
  String get homeNavMasterFingerprint;

  /// No description provided for @homeNavPasteYourHardwareWalletFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Paste your hardware wallet\'s 8-character fingerprint. You can find it in your device\'s settings or identity menu.'**
  String get homeNavPasteYourHardwareWalletFingerprint;

  /// No description provided for @homeNavDerivationPath.
  ///
  /// In en, this message translates to:
  /// **'Derivation path'**
  String get homeNavDerivationPath;

  /// No description provided for @homeNavEnter8HexCharacters.
  ///
  /// In en, this message translates to:
  /// **'Enter 8 hex characters'**
  String get homeNavEnter8HexCharacters;

  /// No description provided for @homeNavMustBeExactly8HexCharacters.
  ///
  /// In en, this message translates to:
  /// **'Must be exactly 8 hex characters (0-9, a-f)'**
  String get homeNavMustBeExactly8HexCharacters;

  /// No description provided for @homeNavBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Bank account'**
  String get homeNavBankAccount;

  /// No description provided for @homeNavPredictionsUnavailableHere.
  ///
  /// In en, this message translates to:
  /// **'Predictions unavailable here'**
  String get homeNavPredictionsUnavailableHere;

  /// No description provided for @hwScanningForDevices.
  ///
  /// In en, this message translates to:
  /// **'Scanning for devices...'**
  String get hwScanningForDevices;

  /// No description provided for @hwNoDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get hwNoDevicesFound;

  /// No description provided for @hwDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device found} other{{count} devices found}}'**
  String hwDevicesFound(int count);

  /// No description provided for @hwLookingForDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for {brand} devices...'**
  String hwLookingForDevices(String brand);

  /// No description provided for @hwNoBrandDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No {brand} devices found'**
  String hwNoBrandDevicesFound(String brand);

  /// No description provided for @hwMakeSureJadeOn.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Jade is powered on with Bluetooth enabled.'**
  String get hwMakeSureJadeOn;

  /// No description provided for @hwMakeSureLedgerUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Ledger is unlocked with Bluetooth enabled.'**
  String get hwMakeSureLedgerUnlocked;

  /// No description provided for @hwJadeDevice.
  ///
  /// In en, this message translates to:
  /// **'Jade device'**
  String get hwJadeDevice;

  /// No description provided for @hwLedgerDevice.
  ///
  /// In en, this message translates to:
  /// **'Ledger device'**
  String get hwLedgerDevice;

  /// No description provided for @hwUsb.
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get hwUsb;

  /// No description provided for @qrModeAnimated.
  ///
  /// In en, this message translates to:
  /// **'Animated'**
  String get qrModeAnimated;

  /// No description provided for @qrModeStatic.
  ///
  /// In en, this message translates to:
  /// **'Static'**
  String get qrModeStatic;

  /// No description provided for @qrSingleCode.
  ///
  /// In en, this message translates to:
  /// **'Single QR code'**
  String get qrSingleCode;

  /// No description provided for @qrDensityBytes.
  ///
  /// In en, this message translates to:
  /// **'Density: {bytes} bytes'**
  String qrDensityBytes(int bytes);

  /// No description provided for @qrFrameCount.
  ///
  /// In en, this message translates to:
  /// **'{count} QR codes'**
  String qrFrameCount(int count);

  /// No description provided for @milestones.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get milestones;

  /// No description provided for @milestoneFirstSatTitle.
  ///
  /// In en, this message translates to:
  /// **'Your first sat'**
  String get milestoneFirstSatTitle;

  /// No description provided for @milestoneFirstSatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You received your first bitcoin.'**
  String get milestoneFirstSatSubtitle;

  /// No description provided for @milestoneHundredKSatsTitle.
  ///
  /// In en, this message translates to:
  /// **'100k sats'**
  String get milestoneHundredKSatsTitle;

  /// No description provided for @milestoneHundredKSatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your balance passed 100,000 sats.'**
  String get milestoneHundredKSatsSubtitle;

  /// No description provided for @milestoneOneMSatsTitle.
  ///
  /// In en, this message translates to:
  /// **'1M sats'**
  String get milestoneOneMSatsTitle;

  /// No description provided for @milestoneOneMSatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your balance passed 1,000,000 sats.'**
  String get milestoneOneMSatsSubtitle;

  /// No description provided for @milestoneFirstLightningTitle.
  ///
  /// In en, this message translates to:
  /// **'First Lightning payment'**
  String get milestoneFirstLightningTitle;

  /// No description provided for @milestoneFirstLightningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You paid over Lightning for the first time.'**
  String get milestoneFirstLightningSubtitle;

  /// No description provided for @milestoneFirstSavingsDepositTitle.
  ///
  /// In en, this message translates to:
  /// **'First savings deposit'**
  String get milestoneFirstSavingsDepositTitle;

  /// No description provided for @milestoneFirstSavingsDepositSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You made your first savings deposit.'**
  String get milestoneFirstSavingsDepositSubtitle;

  /// No description provided for @milestoneFirstPredictionTitle.
  ///
  /// In en, this message translates to:
  /// **'First prediction'**
  String get milestoneFirstPredictionTitle;

  /// No description provided for @milestoneFirstPredictionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You made your first prediction.'**
  String get milestoneFirstPredictionSubtitle;

  /// No description provided for @milestoneFirstWinTitle.
  ///
  /// In en, this message translates to:
  /// **'First winning prediction'**
  String get milestoneFirstWinTitle;

  /// No description provided for @milestoneFirstWinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your first prediction paid out.'**
  String get milestoneFirstWinSubtitle;

  /// No description provided for @accountYourCode.
  ///
  /// In en, this message translates to:
  /// **'Your code'**
  String get accountYourCode;

  /// No description provided for @revealYourRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Reveal your recovery phrase'**
  String get revealYourRecoveryPhrase;

  /// No description provided for @recoveryPhraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get recoveryPhraseTitle;

  /// No description provided for @writeTheseDown.
  ///
  /// In en, this message translates to:
  /// **'Write these down'**
  String get writeTheseDown;

  /// No description provided for @wordsInOrderWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} words in order. Anyone who has them controls your wallet.'**
  String wordsInOrderWarning(int count);

  /// No description provided for @iHaveWrittenDownMyRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'I have written down my recovery phrase.'**
  String get iHaveWrittenDownMyRecoveryPhrase;

  /// No description provided for @selectWallet.
  ///
  /// In en, this message translates to:
  /// **'Select wallet'**
  String get selectWallet;

  /// No description provided for @couldNotLoadRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Could not load your recovery phrase.'**
  String get couldNotLoadRecoveryPhrase;

  /// No description provided for @settingsSupportAndFeedback.
  ///
  /// In en, this message translates to:
  /// **'Support and feedback'**
  String get settingsSupportAndFeedback;

  /// No description provided for @settingsRateTheApp.
  ///
  /// In en, this message translates to:
  /// **'Rate the app'**
  String get settingsRateTheApp;

  /// No description provided for @settingsLeaveAReview.
  ///
  /// In en, this message translates to:
  /// **'Leave a review'**
  String get settingsLeaveAReview;

  /// No description provided for @getHelpFromKuteTeam.
  ///
  /// In en, this message translates to:
  /// **'Get help from the Kute team'**
  String get getHelpFromKuteTeam;

  /// No description provided for @settingsUnlockWithFaceIdOrTouchId.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Face ID or Touch ID'**
  String get settingsUnlockWithFaceIdOrTouchId;

  /// No description provided for @settingsShareUsageAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Share usage analytics'**
  String get settingsShareUsageAnalytics;

  /// No description provided for @settingsShareUsageAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help improve Kute with data on how you use the app'**
  String get settingsShareUsageAnalyticsSubtitle;

  /// No description provided for @settingsPickLightOrDarkBelow.
  ///
  /// In en, this message translates to:
  /// **'Pick light or dark below'**
  String get settingsPickLightOrDarkBelow;

  /// No description provided for @settingsReferralProgram.
  ///
  /// In en, this message translates to:
  /// **'Referral program'**
  String get settingsReferralProgram;

  /// No description provided for @settingsEarnAShareOfFees.
  ///
  /// In en, this message translates to:
  /// **'Earn a share of what Kute makes from your friends'**
  String get settingsEarnAShareOfFees;

  /// No description provided for @settingsExportTransactions.
  ///
  /// In en, this message translates to:
  /// **'Export transactions'**
  String get settingsExportTransactions;

  /// No description provided for @settingsGeneratingReport.
  ///
  /// In en, this message translates to:
  /// **'Generating report'**
  String get settingsGeneratingReport;

  /// No description provided for @settingsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get settingsDone;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get autoLock;

  /// No description provided for @autoLockImmediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get autoLockImmediately;

  /// No description provided for @autoLockAfterOneMinute.
  ///
  /// In en, this message translates to:
  /// **'After 1 minute'**
  String get autoLockAfterOneMinute;

  /// No description provided for @autoLockAfterFiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'After 5 minutes'**
  String get autoLockAfterFiveMinutes;

  /// No description provided for @changePinEnterCurrent.
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN'**
  String get changePinEnterCurrent;

  /// No description provided for @changePinCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create a 6-digit PIN'**
  String get changePinCreateNew;

  /// No description provided for @changePinConfirmNew.
  ///
  /// In en, this message translates to:
  /// **'Confirm your 6-digit PIN'**
  String get changePinConfirmNew;

  /// No description provided for @settingsCustomElectrumNode.
  ///
  /// In en, this message translates to:
  /// **'Custom Bitcoin server'**
  String get settingsCustomElectrumNode;

  /// No description provided for @maximumClaimFee.
  ///
  /// In en, this message translates to:
  /// **'Maximum claim fee'**
  String get maximumClaimFee;

  /// No description provided for @maximumClaimFeeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Set the most you allow this claim to cost, in sats. This is a fee limit, not a confirmation speed. If the required fee is higher, the claim will stop.'**
  String get maximumClaimFeeExplanation;

  /// No description provided for @depositRefundSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Refund submitted. Waiting for confirmation.'**
  String get depositRefundSubmitted;

  /// No description provided for @depositActionWalletChanged.
  ///
  /// In en, this message translates to:
  /// **'The wallet changed. Reopen the deposit to continue.'**
  String get depositActionWalletChanged;

  /// No description provided for @depositActionBusy.
  ///
  /// In en, this message translates to:
  /// **'This deposit already has an action in progress.'**
  String get depositActionBusy;

  /// No description provided for @depositActionWalletUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The wallet is not ready. Unlock the app, wait a moment and try again.'**
  String get depositActionWalletUnavailable;

  /// No description provided for @depositActionInvalidDeposit.
  ///
  /// In en, this message translates to:
  /// **'This deposit could not be read. Refresh and try again.'**
  String get depositActionInvalidDeposit;

  /// No description provided for @depositActionImmature.
  ///
  /// In en, this message translates to:
  /// **'This deposit is still waiting for confirmations.'**
  String get depositActionImmature;

  /// No description provided for @depositActionRefundInProgress.
  ///
  /// In en, this message translates to:
  /// **'This deposit already has a refund in progress.'**
  String get depositActionRefundInProgress;

  /// No description provided for @depositActionInvalidFee.
  ///
  /// In en, this message translates to:
  /// **'The maximum claim fee must be above zero and less than the deposit.'**
  String get depositActionInvalidFee;

  /// No description provided for @depositAlreadyReceived.
  ///
  /// In en, this message translates to:
  /// **'This deposit was already received. Updating your balance.'**
  String get depositAlreadyReceived;

  /// No description provided for @depositNoLongerPending.
  ///
  /// In en, this message translates to:
  /// **'This deposit is no longer pending. Refreshing its status.'**
  String get depositNoLongerPending;

  /// No description provided for @depositRefundBroadcastUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'The refund was signed, but its broadcast was not confirmed. Check its status again later.'**
  String get depositRefundBroadcastUnconfirmed;

  /// No description provided for @claimFeeLastQuote.
  ///
  /// In en, this message translates to:
  /// **'Suggested from the last quote of {sats} sats, plus some headroom.'**
  String claimFeeLastQuote(String sats);

  /// No description provided for @claimFeeQuoteExceedsDeposit.
  ///
  /// In en, this message translates to:
  /// **'The last claim quote was {sats} sats, which would use up this deposit. You can wait for lower fees or refund it.'**
  String claimFeeQuoteExceedsDeposit(String sats);

  /// No description provided for @depositClaimStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Your claim may have been submitted. Checking the deposit status.'**
  String get depositClaimStatusUnknown;

  /// No description provided for @confirmationBitcoinSent.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin sent'**
  String get confirmationBitcoinSent;

  /// No description provided for @confirmationWalletBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Wallet backed up'**
  String get confirmationWalletBackedUp;

  /// No description provided for @confirmationPinUpdated.
  ///
  /// In en, this message translates to:
  /// **'PIN updated'**
  String get confirmationPinUpdated;

  /// No description provided for @confirmationWalletRecovered.
  ///
  /// In en, this message translates to:
  /// **'Wallet recovered'**
  String get confirmationWalletRecovered;

  /// No description provided for @confirmationSentToWallet.
  ///
  /// In en, this message translates to:
  /// **'Sent to {walletName}'**
  String confirmationSentToWallet(String walletName);

  /// No description provided for @confirmationOrderFilled.
  ///
  /// In en, this message translates to:
  /// **'Order filled'**
  String get confirmationOrderFilled;

  /// No description provided for @confirmationWinningsClaimed.
  ///
  /// In en, this message translates to:
  /// **'Winnings claimed'**
  String get confirmationWinningsClaimed;

  /// No description provided for @guardQuoteRejected.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify this transfer, so nothing was sent. Please try again.'**
  String get guardQuoteRejected;

  /// No description provided for @guardAmountTooSmall.
  ///
  /// In en, this message translates to:
  /// **'This transfer would lose too much to fees, so nothing was sent. Try a larger amount.'**
  String get guardAmountTooSmall;

  /// No description provided for @guardQuoteExpired.
  ///
  /// In en, this message translates to:
  /// **'This price expired. Check the updated amount and confirm again.'**
  String get guardQuoteExpired;

  /// No description provided for @guardDepositTermsRejected.
  ///
  /// In en, this message translates to:
  /// **'Investing deposits are unavailable right now. Nothing was sent.'**
  String get guardDepositTermsRejected;

  /// No description provided for @guardWithdrawDestinationRejected.
  ///
  /// In en, this message translates to:
  /// **'This withdrawal address couldn\'t be verified, so nothing was withdrawn.'**
  String get guardWithdrawDestinationRejected;

  /// No description provided for @investingAccountNotReady.
  ///
  /// In en, this message translates to:
  /// **'Your Investing account isn\'t ready yet. Open Investing once, then try again.'**
  String get investingAccountNotReady;

  /// No description provided for @invalidRecipientNothingSent.
  ///
  /// In en, this message translates to:
  /// **'Invalid recipient address. Nothing was sent.'**
  String get invalidRecipientNothingSent;

  /// No description provided for @walletSessionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify your wallet right now, so nothing was sent. Please try again in a moment.'**
  String get walletSessionUnavailable;

  /// No description provided for @ledgerErrorLocked.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is locked. Unlock it and try again.'**
  String get ledgerErrorLocked;

  /// No description provided for @ledgerErrorOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open the {app} app on your Ledger and try again.'**
  String ledgerErrorOpenApp(String app);

  /// No description provided for @ledgerErrorInstallApp.
  ///
  /// In en, this message translates to:
  /// **'Install the {app} app on your Ledger with Ledger Live.'**
  String ledgerErrorInstallApp(String app);

  /// No description provided for @ledgerErrorUpdateApp.
  ///
  /// In en, this message translates to:
  /// **'Update the {app} app on your Ledger with Ledger Live.'**
  String ledgerErrorUpdateApp(String app);

  /// No description provided for @ledgerErrorRejected.
  ///
  /// In en, this message translates to:
  /// **'You rejected the request on your Ledger. Nothing was sent.'**
  String get ledgerErrorRejected;

  /// No description provided for @ledgerErrorDataRejected.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger rejected this data. Check the wallet address type or the app settings on your Ledger.'**
  String get ledgerErrorDataRejected;

  /// No description provided for @ledgerErrorPayloadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This request is too large for your Ledger.'**
  String get ledgerErrorPayloadTooLarge;

  /// No description provided for @ledgerErrorDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger disconnected before approving. Nothing was sent.'**
  String get ledgerErrorDisconnected;

  /// No description provided for @ledgerErrorWrongDevice.
  ///
  /// In en, this message translates to:
  /// **'This Ledger does not match this account.'**
  String get ledgerErrorWrongDevice;

  /// No description provided for @ledgerErrorWrongSigner.
  ///
  /// In en, this message translates to:
  /// **'The signature from your Ledger does not match this account. Nothing was sent.'**
  String get ledgerErrorWrongSigner;

  /// No description provided for @ledgerErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger did not respond in time. Try again.'**
  String get ledgerErrorTimeout;

  /// No description provided for @ledgerErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is still handling another request. Finish it first.'**
  String get ledgerErrorBusy;

  /// No description provided for @ledgerErrorPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access for Kute in Settings to connect your Ledger.'**
  String get ledgerErrorPermission;

  /// No description provided for @ledgerErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with your Ledger. Try again.'**
  String get ledgerErrorUnknown;

  /// No description provided for @ledgerErrorUnknownCode.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with your Ledger (code {code}). Try again.'**
  String ledgerErrorUnknownCode(String code);

  /// No description provided for @ledgerTransportLabel.
  ///
  /// In en, this message translates to:
  /// **'Connect with'**
  String get ledgerTransportLabel;

  /// No description provided for @ledgerMakeSureUnlockedUsb.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Ledger is unlocked and connected with a USB cable.'**
  String get ledgerMakeSureUnlockedUsb;

  /// No description provided for @ledgerVenueIconsLabel.
  ///
  /// In en, this message translates to:
  /// **'Works with Hyperliquid and Polymarket'**
  String get ledgerVenueIconsLabel;

  /// No description provided for @ledgerConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger'**
  String get ledgerConnectTitle;

  /// No description provided for @ledgerTabBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin'**
  String get ledgerTabBitcoin;

  /// No description provided for @ledgerTabInvesting.
  ///
  /// In en, this message translates to:
  /// **'Investing'**
  String get ledgerTabInvesting;

  /// No description provided for @ledgerTabInvestingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Investing, Hyperliquid'**
  String get ledgerTabInvestingSemantics;

  /// No description provided for @ledgerTabPredictions.
  ///
  /// In en, this message translates to:
  /// **'Predictions'**
  String get ledgerTabPredictions;

  /// No description provided for @ledgerTabPredictionsSemantics.
  ///
  /// In en, this message translates to:
  /// **'Predictions, Polymarket'**
  String get ledgerTabPredictionsSemantics;

  /// No description provided for @ledgerEnableInvestingTitle.
  ///
  /// In en, this message translates to:
  /// **'Use this Ledger for investing'**
  String get ledgerEnableInvestingTitle;

  /// No description provided for @ledgerPartialLoad.
  ///
  /// In en, this message translates to:
  /// **'Some balances could not load'**
  String get ledgerPartialLoad;

  /// No description provided for @ledgerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get ledgerRetry;

  /// No description provided for @ledgerBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get ledgerBalanceUnavailable;

  /// No description provided for @ledgerInvestCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to invest'**
  String get ledgerInvestCta;

  /// No description provided for @ledgerSetupTurnOnCta.
  ///
  /// In en, this message translates to:
  /// **'Turn on investing'**
  String get ledgerSetupTurnOnCta;

  /// No description provided for @ledgerSetupTurnedOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Investing turned on'**
  String get ledgerSetupTurnedOnTitle;

  /// No description provided for @ledgerSetupBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger can also hold your Investing and Predictions accounts. Confirm it once on the device. After that, every investment and prediction needs your approval there.'**
  String get ledgerSetupBodyPlain;

  /// No description provided for @ledgerSetupStepCheck.
  ///
  /// In en, this message translates to:
  /// **'Check this Ledger'**
  String get ledgerSetupStepCheck;

  /// No description provided for @ledgerSetupStepConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm on Ledger'**
  String get ledgerSetupStepConfirm;

  /// No description provided for @ledgerEnableInvestingBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Confirm once on your Ledger to see Investing and Predictions here. Every action still needs your approval on the device.'**
  String get ledgerEnableInvestingBodyPlain;

  /// No description provided for @ledgerTurnOnInvestingFirst.
  ///
  /// In en, this message translates to:
  /// **'Turn on investing for this Ledger first.'**
  String get ledgerTurnOnInvestingFirst;

  /// No description provided for @ledgerTransferSubtitlePlain.
  ///
  /// In en, this message translates to:
  /// **'Move money between cash and your investing balance.'**
  String get ledgerTransferSubtitlePlain;

  /// No description provided for @ledgerTransferToInvesting.
  ///
  /// In en, this message translates to:
  /// **'To investing balance'**
  String get ledgerTransferToInvesting;

  /// No description provided for @ledgerTransferToCash.
  ///
  /// In en, this message translates to:
  /// **'To cash'**
  String get ledgerTransferToCash;

  /// No description provided for @ledgerHlCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get ledgerHlCash;

  /// No description provided for @ledgerHlInvestingBalance.
  ///
  /// In en, this message translates to:
  /// **'Investing balance'**
  String get ledgerHlInvestingBalance;

  /// No description provided for @ledgerActivityMergedShares.
  ///
  /// In en, this message translates to:
  /// **'Merged shares'**
  String get ledgerActivityMergedShares;

  /// No description provided for @ledgerActivitySplitShares.
  ///
  /// In en, this message translates to:
  /// **'Split shares'**
  String get ledgerActivitySplitShares;

  /// No description provided for @ledgerFeeFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get ledgerFeeFree;

  /// No description provided for @ledgerFeeRelayerNote.
  ///
  /// In en, this message translates to:
  /// **'Kute\'s relayer pays the Polygon network fee. Nothing is taken from this amount.'**
  String get ledgerFeeRelayerNote;

  /// No description provided for @ledgerHowThisWorks.
  ///
  /// In en, this message translates to:
  /// **'How this works'**
  String get ledgerHowThisWorks;

  /// No description provided for @ledgerFundIntroLine.
  ///
  /// In en, this message translates to:
  /// **'You approve twice on your Ledger. Funds are ready after the network confirms, usually within an hour.'**
  String get ledgerFundIntroLine;

  /// No description provided for @ledgerPmFundIntroLine.
  ///
  /// In en, this message translates to:
  /// **'You approve twice on your Ledger now, and once more when the bitcoin arrives.'**
  String get ledgerPmFundIntroLine;

  /// No description provided for @ledgerWithdrawIntroLine.
  ///
  /// In en, this message translates to:
  /// **'You confirm the receiving address and the withdrawal on your Ledger. Bitcoin arrives after the network confirms.'**
  String get ledgerWithdrawIntroLine;

  /// No description provided for @ledgerWithdrawExplainSteps.
  ///
  /// In en, this message translates to:
  /// **'Confirm your receiving Bitcoin address and the withdrawal on your Ledger. Moving money out of your investing balance may need one more confirmation.'**
  String get ledgerWithdrawExplainSteps;

  /// No description provided for @ledgerFundArrivalPlain.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin arrives at your Ledger after the network confirms.'**
  String get ledgerFundArrivalPlain;

  /// No description provided for @ledgerFundExplainCashSeparate.
  ///
  /// In en, this message translates to:
  /// **'The money lands as cash in your Investing account. Moving it to your investing balance is a separate step.'**
  String get ledgerFundExplainCashSeparate;

  /// No description provided for @ledgerArrivesAfterNetwork.
  ///
  /// In en, this message translates to:
  /// **'Arrives after the network confirms.'**
  String get ledgerArrivesAfterNetwork;

  /// No description provided for @ledgerSubmitPendingPlain.
  ///
  /// In en, this message translates to:
  /// **'Sent. We are still confirming it.'**
  String get ledgerSubmitPendingPlain;

  /// No description provided for @ledgerFundReviewProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get ledgerFundReviewProvider;

  /// No description provided for @ledgerPmFundGasTitlePlain.
  ///
  /// In en, this message translates to:
  /// **'Network fees are covered'**
  String get ledgerPmFundGasTitlePlain;

  /// No description provided for @ledgerPmFundGasBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Kute pays the network fee for this step. The conversion fee is shown in the quote before you approve.'**
  String get ledgerPmFundGasBodyPlain;

  /// No description provided for @ledgerPmFundSheetGasPlain.
  ///
  /// In en, this message translates to:
  /// **'Kute pays the network fee for this step.'**
  String get ledgerPmFundSheetGasPlain;

  /// No description provided for @ledgerPmWithdrawArrivalBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin arrives after the network confirms. This can take up to an hour.'**
  String get ledgerPmWithdrawArrivalBodyPlain;

  /// No description provided for @ledgerWithdrawSentPlain.
  ///
  /// In en, this message translates to:
  /// **'Sent. Arrives after the network confirms.'**
  String get ledgerWithdrawSentPlain;

  /// No description provided for @ledgerFailureCodeDetail.
  ///
  /// In en, this message translates to:
  /// **'Ledger code {code}'**
  String ledgerFailureCodeDetail(String code);

  /// No description provided for @ledgerAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get ledgerAdvancedTitle;

  /// No description provided for @ledgerActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get ledgerActivityEmpty;

  /// No description provided for @ledgerSetupStepSave.
  ///
  /// In en, this message translates to:
  /// **'Save the account'**
  String get ledgerSetupStepSave;

  /// No description provided for @ledgerSetupCompareAddress.
  ///
  /// In en, this message translates to:
  /// **'Compare this address with the one on your Ledger screen. Approve on the device only if they match.'**
  String get ledgerSetupCompareAddress;

  /// No description provided for @ledgerSetupWhyBothApps.
  ///
  /// In en, this message translates to:
  /// **'The Bitcoin checks before and after confirm that the same Ledger and passphrase hold both accounts.'**
  String get ledgerSetupWhyBothApps;

  /// No description provided for @ledgerFundBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get ledgerFundBalanceLabel;

  /// No description provided for @ledgerPositionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get ledgerPositionsTitle;

  /// No description provided for @ledgerInvestingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No investments yet'**
  String get ledgerInvestingEmpty;

  /// No description provided for @ledgerSideBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get ledgerSideBuy;

  /// No description provided for @ledgerSideSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get ledgerSideSell;

  /// No description provided for @ledgerOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'{side} {size} at {price}'**
  String ledgerOrderSummary(String side, String size, String price);

  /// No description provided for @ledgerClaimCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to claim'**
  String get ledgerClaimCta;

  /// No description provided for @ledgerSellCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to sell'**
  String get ledgerSellCta;

  /// No description provided for @ledgerPmLegacyReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This Predictions account is not supported in Kute yet. You can see it here but not act on it.'**
  String get ledgerPmLegacyReadOnly;

  /// No description provided for @ledgerPmClaimable.
  ///
  /// In en, this message translates to:
  /// **'Ready to claim'**
  String get ledgerPmClaimable;

  /// Caption of a Predictions position whose market has ended but whose result is not claimable yet (Polymarket resolves it within minutes).
  ///
  /// In en, this message translates to:
  /// **'Ended · Result in a few minutes'**
  String get polyAwaitingResult;

  /// Caption of an ended Predictions position whose side is at ~100%: it won and becomes claimable within minutes.
  ///
  /// In en, this message translates to:
  /// **'You won · Ready to claim in a few minutes'**
  String get polyAwaitingWon;

  /// Caption of an ended Predictions position whose side is at ~0%.
  ///
  /// In en, this message translates to:
  /// **'Ended · Lost'**
  String get polyAwaitingLost;

  /// Caption of a Predictions position whose game or market has ended but whose result is not claimable yet (a game usually resolves 15 minutes to 2 hours after it ends).
  ///
  /// In en, this message translates to:
  /// **'Ended · Waiting for the result'**
  String get polyAwaitingResultSoon;

  /// Caption of an ended game or market position whose side is at ~100%: it won and becomes claimable once the result is in.
  ///
  /// In en, this message translates to:
  /// **'You won · Ready to claim soon'**
  String get polyAwaitingWonSoon;

  /// Caption of an ended Predictions position whose result is not in yet, when Polymarket publishes when the proposed result settles. minutes is the time left, rounded up, under an hour.
  ///
  /// In en, this message translates to:
  /// **'Ended · Result in about {minutes} min'**
  String polyAwaitingResultInMinutes(int minutes);

  /// Same caption when an hour or more is left. hours is the time left, rounded.
  ///
  /// In en, this message translates to:
  /// **'Ended · Result in about {hours} h'**
  String polyAwaitingResultInHours(int hours);

  /// Same caption when less than a minute is left.
  ///
  /// In en, this message translates to:
  /// **'Ended · Result in under a minute'**
  String get polyAwaitingResultUnderMinute;

  /// Caption of an ended Predictions position whose side is at ~100%, when Polymarket publishes when the result settles (it becomes claimable then). minutes is the time left, rounded up, under an hour.
  ///
  /// In en, this message translates to:
  /// **'You won · Ready to claim in about {minutes} min'**
  String polyAwaitingWonInMinutes(int minutes);

  /// Same caption when an hour or more is left. hours is the time left, rounded.
  ///
  /// In en, this message translates to:
  /// **'You won · Ready to claim in about {hours} h'**
  String polyAwaitingWonInHours(int hours);

  /// Same caption when less than a minute is left.
  ///
  /// In en, this message translates to:
  /// **'You won · Ready to claim in under a minute'**
  String get polyAwaitingWonUnderMinute;

  /// No description provided for @ledgerSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Invest with your Ledger'**
  String get ledgerSetupTitle;

  /// No description provided for @ledgerSetupTryAgainCta.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get ledgerSetupTryAgainCta;

  /// No description provided for @ledgerSetupBitcoinOnlyCta.
  ///
  /// In en, this message translates to:
  /// **'Keep Bitcoin only'**
  String get ledgerSetupBitcoinOnlyCta;

  /// No description provided for @ledgerSetupStepConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to your Ledger'**
  String get ledgerSetupStepConnecting;

  /// No description provided for @ledgerSetupStepOpenBitcoinApp.
  ///
  /// In en, this message translates to:
  /// **'Open the Bitcoin app on your Ledger'**
  String get ledgerSetupStepOpenBitcoinApp;

  /// No description provided for @ledgerSetupStepCheckingAccount.
  ///
  /// In en, this message translates to:
  /// **'Checking account'**
  String get ledgerSetupStepCheckingAccount;

  /// No description provided for @ledgerSetupStepOpenEthereumApp.
  ///
  /// In en, this message translates to:
  /// **'Open the Ethereum app on your Ledger'**
  String get ledgerSetupStepOpenEthereumApp;

  /// No description provided for @ledgerSetupStepApproveAddress.
  ///
  /// In en, this message translates to:
  /// **'Check the address on your Ledger and approve'**
  String get ledgerSetupStepApproveAddress;

  /// No description provided for @ledgerSetupStepSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get ledgerSetupStepSaving;

  /// No description provided for @ledgerAppAuthReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm it is you to approve with your Ledger'**
  String get ledgerAppAuthReason;

  /// No description provided for @ledgerApprovalConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect your Ledger'**
  String get ledgerApprovalConnectTitle;

  /// No description provided for @ledgerApprovalConnectBody.
  ///
  /// In en, this message translates to:
  /// **'Choose how your Ledger connects to this phone.'**
  String get ledgerApprovalConnectBody;

  /// No description provided for @ledgerApprovalBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get ledgerApprovalBluetooth;

  /// No description provided for @ledgerApprovalUsb.
  ///
  /// In en, this message translates to:
  /// **'USB cable'**
  String get ledgerApprovalUsb;

  /// No description provided for @ledgerApprovalScanningTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for your Ledger'**
  String get ledgerApprovalScanningTitle;

  /// No description provided for @ledgerApprovalScanningBody.
  ///
  /// In en, this message translates to:
  /// **'Turn on your Ledger, unlock it and keep it close to your phone.'**
  String get ledgerApprovalScanningBody;

  /// No description provided for @ledgerApprovalNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No Ledger found yet'**
  String get ledgerApprovalNoDevices;

  /// No description provided for @ledgerApprovalScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get ledgerApprovalScanAgain;

  /// No description provided for @ledgerApprovalConnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get ledgerApprovalConnectingTitle;

  /// No description provided for @ledgerApprovalConnectingBody.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger unlocked and nearby.'**
  String get ledgerApprovalConnectingBody;

  /// No description provided for @ledgerUnlockStep.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger'**
  String get ledgerUnlockStep;

  /// No description provided for @ledgerUnlockStepBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN on the Ledger, then tap Try again.'**
  String get ledgerUnlockStepBody;

  /// No description provided for @ledgerOpenAppStep.
  ///
  /// In en, this message translates to:
  /// **'Open the Ethereum app on your Ledger'**
  String get ledgerOpenAppStep;

  /// No description provided for @ledgerOpenAppStepBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm on your Ledger if it asks to open the app.'**
  String get ledgerOpenAppStepBody;

  /// No description provided for @ledgerOpenAppRetryBody.
  ///
  /// In en, this message translates to:
  /// **'Open the Ethereum app on your Ledger, then tap Try again.'**
  String get ledgerOpenAppRetryBody;

  /// No description provided for @ledgerInstallAppStep.
  ///
  /// In en, this message translates to:
  /// **'Install the Ethereum app on your Ledger with Ledger Live'**
  String get ledgerInstallAppStep;

  /// No description provided for @ledgerUpdateAppStep.
  ///
  /// In en, this message translates to:
  /// **'Update the Ethereum app on your Ledger with Ledger Live'**
  String get ledgerUpdateAppStep;

  /// No description provided for @ledgerAppStoreRetryBody.
  ///
  /// In en, this message translates to:
  /// **'When it is done, tap Try again.'**
  String get ledgerAppStoreRetryBody;

  /// No description provided for @ledgerCheckingAccountStep.
  ///
  /// In en, this message translates to:
  /// **'Checking account'**
  String get ledgerCheckingAccountStep;

  /// No description provided for @ledgerCheckingAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Making sure this Ledger matches this account.'**
  String get ledgerCheckingAccountBody;

  /// No description provided for @ledgerReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get ledgerReviewTitle;

  /// No description provided for @ledgerReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Check the details. Nothing happens until you approve on your Ledger.'**
  String get ledgerReviewBody;

  /// No description provided for @ledgerReadableNote.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger shows these details. Check they match before you approve.'**
  String get ledgerReadableNote;

  /// No description provided for @ledgerOpaqueNote.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger shows a code, not the details. Check the details here before you approve.'**
  String get ledgerOpaqueNote;

  /// No description provided for @ledgerApproveStep.
  ///
  /// In en, this message translates to:
  /// **'Approve on Ledger'**
  String get ledgerApproveStep;

  /// No description provided for @ledgerApproveStepBody.
  ///
  /// In en, this message translates to:
  /// **'Check the request on your Ledger and approve it there.'**
  String get ledgerApproveStepBody;

  /// No description provided for @ledgerSubmittingStep.
  ///
  /// In en, this message translates to:
  /// **'Submitting'**
  String get ledgerSubmittingStep;

  /// No description provided for @ledgerSubmittingBody.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger approved. Sending the request now.'**
  String get ledgerSubmittingBody;

  /// No description provided for @ledgerPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Submitted. Waiting for confirmation.'**
  String get ledgerPendingStatus;

  /// No description provided for @ledgerPendingBody.
  ///
  /// In en, this message translates to:
  /// **'You can close this. We keep checking and never send it twice.'**
  String get ledgerPendingBody;

  /// No description provided for @ledgerCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get ledgerCheckStatus;

  /// No description provided for @ledgerApprovalFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get ledgerApprovalFailedTitle;

  /// No description provided for @ledgerApproveAgain.
  ///
  /// In en, this message translates to:
  /// **'Approve again'**
  String get ledgerApproveAgain;

  /// No description provided for @ledgerApprovalClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get ledgerApprovalClose;

  /// No description provided for @ledgerRejectedAfterSignature.
  ///
  /// In en, this message translates to:
  /// **'You rejected a request on your Ledger. Check your activity before trying again.'**
  String get ledgerRejectedAfterSignature;

  /// No description provided for @ledgerDisconnectedAfterSignature.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger disconnected after approving. Check your activity before trying again.'**
  String get ledgerDisconnectedAfterSignature;

  /// No description provided for @ledgerErrorCheckActivity.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong after your Ledger approved. Check your activity before trying again.'**
  String get ledgerErrorCheckActivity;

  /// No description provided for @ledgerErrorAppAuthDeclined.
  ///
  /// In en, this message translates to:
  /// **'Confirm it is you to continue.'**
  String get ledgerErrorAppAuthDeclined;

  /// No description provided for @ledgerErrorActionBlocked.
  ///
  /// In en, this message translates to:
  /// **'This action is not available for Ledger accounts yet.'**
  String get ledgerErrorActionBlocked;

  /// No description provided for @ledgerErrorGeoBlocked.
  ///
  /// In en, this message translates to:
  /// **'Investing is restricted in the region your internet connection appears to be in. If that isn\'t where you are, check your network or VPN settings and try again.'**
  String get ledgerErrorGeoBlocked;

  /// No description provided for @ledgerErrorTradingDisabled.
  ///
  /// In en, this message translates to:
  /// **'Investing is temporarily unavailable. Try again later.'**
  String get ledgerErrorTradingDisabled;

  /// No description provided for @ledgerErrorAccountUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This predictions account is not supported in Kute yet.'**
  String get ledgerErrorAccountUnsupported;

  /// No description provided for @ledgerErrorDetailsChanged.
  ///
  /// In en, this message translates to:
  /// **'The details changed. Review again before approving.'**
  String get ledgerErrorDetailsChanged;

  /// No description provided for @ledgerErrorNonceRejected.
  ///
  /// In en, this message translates to:
  /// **'The request expired before it was accepted. Approve again to retry.'**
  String get ledgerErrorNonceRejected;

  /// No description provided for @ledgerErrorVenueRejected.
  ///
  /// In en, this message translates to:
  /// **'The request was not accepted. Nothing changed in your account.'**
  String get ledgerErrorVenueRejected;

  /// No description provided for @ledgerPriceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get ledgerPriceUnavailable;

  /// No description provided for @ledgerAvailableAmount.
  ///
  /// In en, this message translates to:
  /// **'Available: {amount}'**
  String ledgerAvailableAmount(String amount);

  /// No description provided for @ledgerSummaryAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get ledgerSummaryAction;

  /// No description provided for @ledgerSummaryAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get ledgerSummaryAmount;

  /// No description provided for @ledgerSummaryMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get ledgerSummaryMarket;

  /// No description provided for @ledgerSummaryOutcome.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get ledgerSummaryOutcome;

  /// No description provided for @ledgerSummaryShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get ledgerSummaryShares;

  /// No description provided for @ledgerSummaryMinProceeds.
  ///
  /// In en, this message translates to:
  /// **'You receive at least'**
  String get ledgerSummaryMinProceeds;

  /// No description provided for @ledgerSummaryDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get ledgerSummaryDestination;

  /// No description provided for @ledgerSummaryFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get ledgerSummaryFrom;

  /// No description provided for @ledgerSummaryTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get ledgerSummaryTo;

  /// No description provided for @ledgerSummarySide.
  ///
  /// In en, this message translates to:
  /// **'Side'**
  String get ledgerSummarySide;

  /// No description provided for @ledgerSummarySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get ledgerSummarySize;

  /// No description provided for @ledgerSummaryLeverage.
  ///
  /// In en, this message translates to:
  /// **'Leverage'**
  String get ledgerSummaryLeverage;

  /// No description provided for @ledgerSummaryPriceType.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get ledgerSummaryPriceType;

  /// No description provided for @ledgerSummaryLimitPrice.
  ///
  /// In en, this message translates to:
  /// **'Worst price'**
  String get ledgerSummaryLimitPrice;

  /// No description provided for @ledgerSummaryFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Fee rate'**
  String get ledgerSummaryFeeRate;

  /// No description provided for @ledgerSummaryBuilder.
  ///
  /// In en, this message translates to:
  /// **'Fee recipient'**
  String get ledgerSummaryBuilder;

  /// No description provided for @ledgerSellSlippageNote.
  ///
  /// In en, this message translates to:
  /// **'Sells now at the best available price, at most 5% below the current bid.'**
  String get ledgerSellSlippageNote;

  /// No description provided for @ledgerSellTooSmall.
  ///
  /// In en, this message translates to:
  /// **'This amount is too small to sell.'**
  String get ledgerSellTooSmall;

  /// No description provided for @ledgerSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get ledgerSold;

  /// No description provided for @ledgerClaimTitle.
  ///
  /// In en, this message translates to:
  /// **'Claim winnings'**
  String get ledgerClaimTitle;

  /// No description provided for @ledgerClaimSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Each claim is approved on your Ledger.'**
  String get ledgerClaimSubtitle;

  /// No description provided for @ledgerClaimOneAtATime.
  ///
  /// In en, this message translates to:
  /// **'Claims are approved one market at a time.'**
  String get ledgerClaimOneAtATime;

  /// No description provided for @ledgerClaimNotReady.
  ///
  /// In en, this message translates to:
  /// **'This result is not final yet. Try again later.'**
  String get ledgerClaimNotReady;

  /// No description provided for @ledgerClaimRowSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get ledgerClaimRowSubmitted;

  /// No description provided for @ledgerClaimRowPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get ledgerClaimRowPending;

  /// No description provided for @ledgerClaimSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Claim submitted. Funds arrive after the network confirms.'**
  String get ledgerClaimSubmitted;

  /// No description provided for @ledgerWithdrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw to Bitcoin'**
  String get ledgerWithdrawTitle;

  /// No description provided for @ledgerWithdrawSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sends your predictions cash to your Ledger Bitcoin account.'**
  String get ledgerWithdrawSubtitle;

  /// No description provided for @ledgerWithdrawDestination.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger Bitcoin account'**
  String get ledgerWithdrawDestination;

  /// No description provided for @ledgerWithdrawCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to withdraw'**
  String get ledgerWithdrawCta;

  /// No description provided for @ledgerWithdrawUnwrapFirst.
  ///
  /// In en, this message translates to:
  /// **'First make these funds withdrawable. This is a separate approval on your Ledger.'**
  String get ledgerWithdrawUnwrapFirst;

  /// No description provided for @ledgerWithdrawUnwrapCta.
  ///
  /// In en, this message translates to:
  /// **'Make funds withdrawable'**
  String get ledgerWithdrawUnwrapCta;

  /// No description provided for @ledgerWithdrawNotEnough.
  ///
  /// In en, this message translates to:
  /// **'There is not enough cash in this account for this amount.'**
  String get ledgerWithdrawNotEnough;

  /// No description provided for @ledgerUnwrapSummary.
  ///
  /// In en, this message translates to:
  /// **'Make funds withdrawable'**
  String get ledgerUnwrapSummary;

  /// No description provided for @ledgerUnwrapDone.
  ///
  /// In en, this message translates to:
  /// **'Funds are ready to withdraw'**
  String get ledgerUnwrapDone;

  /// No description provided for @ledgerTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Move funds'**
  String get ledgerTransferTitle;

  /// No description provided for @ledgerMoveCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to move'**
  String get ledgerMoveCta;

  /// No description provided for @ledgerTransferDone.
  ///
  /// In en, this message translates to:
  /// **'Funds moved'**
  String get ledgerTransferDone;

  /// No description provided for @ledgerOpaqueActionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing with a Ledger is not available yet. Your Ledger would show a code instead of the details, so we keep this off for now.'**
  String get ledgerOpaqueActionsUnavailable;

  /// No description provided for @depositToTrade.
  ///
  /// In en, this message translates to:
  /// **'Deposit to invest'**
  String get depositToTrade;

  /// No description provided for @depositToPredict.
  ///
  /// In en, this message translates to:
  /// **'Deposit to predict'**
  String get depositToPredict;

  /// A Predictions or Investing slip's disabled button while a deposit into that venue is on its way. amount is the estimated dollars arriving.
  ///
  /// In en, this message translates to:
  /// **'Deposit incoming · {amount}'**
  String slipDepositIncoming(String amount);

  /// Small line under the Deposit incoming button. States no arrival time, because the app is not told one.
  ///
  /// In en, this message translates to:
  /// **'Your money is on its way. This button unlocks when it lands.'**
  String get slipDepositIncomingNote;

  /// Small link under Deposit incoming when the deposit on its way does not cover the order; opens a deposit prefilled with the rest.
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get slipDepositAddMore;

  /// Line above the slip's deposit button after a deposit the slip was waiting on failed or was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Your deposit didn\'t go through. You can deposit again.'**
  String get slipDepositFailedNote;

  /// No description provided for @ledgerOrderStepsNote.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger may ask for up to three approvals: a one time fee approval, the leverage and the order.'**
  String get ledgerOrderStepsNote;

  /// No description provided for @ledgerOrderMarketPrice.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get ledgerOrderMarketPrice;

  /// No description provided for @ledgerOrderTooSmall.
  ///
  /// In en, this message translates to:
  /// **'This amount is below the minimum order size.'**
  String get ledgerOrderTooSmall;

  /// No description provided for @ledgerOrderFilled.
  ///
  /// In en, this message translates to:
  /// **'Filled'**
  String get ledgerOrderFilled;

  /// No description provided for @ledgerOrderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Order placed'**
  String get ledgerOrderPlaced;

  /// No description provided for @ledgerOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get ledgerOrderCancelled;

  /// No description provided for @ledgerCancelOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get ledgerCancelOrderSummary;

  /// No description provided for @ledgerCancelOrderCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to cancel'**
  String get ledgerCancelOrderCta;

  /// No description provided for @ledgerVerifyAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the address on your Ledger'**
  String get ledgerVerifyAddressTitle;

  /// No description provided for @ledgerVerifyAddressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your bitcoin goes to this address on {name}. Approve on your Ledger only if it shows the same address.'**
  String ledgerVerifyAddressSubtitle(String name);

  /// No description provided for @ledgerVerifyAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get ledgerVerifyAddressLabel;

  /// No description provided for @ledgerVerifyAddressButton.
  ///
  /// In en, this message translates to:
  /// **'Verify on Ledger'**
  String get ledgerVerifyAddressButton;

  /// No description provided for @ledgerVerifyAddressWaiting.
  ///
  /// In en, this message translates to:
  /// **'Check your Ledger. Approve only if the address matches.'**
  String get ledgerVerifyAddressWaiting;

  /// No description provided for @ledgerVerifyAddressMismatch.
  ///
  /// In en, this message translates to:
  /// **'The address on your Ledger does not match. Nothing was bought.'**
  String get ledgerVerifyAddressMismatch;

  /// No description provided for @ledgerVerifyAddressUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This Ledger account cannot show its address. Nothing was bought.'**
  String get ledgerVerifyAddressUnavailable;

  /// No description provided for @ledgerCashAppAddressNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Confirm the address on your Ledger to buy with Cash App.'**
  String get ledgerCashAppAddressNotVerified;

  /// No description provided for @routeUnavailableNothingSent.
  ///
  /// In en, this message translates to:
  /// **'This transfer isn\'t available right now. Nothing was sent.'**
  String get routeUnavailableNothingSent;

  /// No description provided for @routeAmountTooSmall.
  ///
  /// In en, this message translates to:
  /// **'The minimum for this transfer is {minimum}.'**
  String routeAmountTooSmall(String minimum);

  /// No description provided for @routeAmountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The maximum for this transfer is {maximum}.'**
  String routeAmountTooLarge(String maximum);

  /// No description provided for @routeAmountTooSmallGeneric.
  ///
  /// In en, this message translates to:
  /// **'This amount is below the minimum for this transfer.'**
  String get routeAmountTooSmallGeneric;

  /// No description provided for @routeAmountTooLargeGeneric.
  ///
  /// In en, this message translates to:
  /// **'This amount is above the maximum for this transfer.'**
  String get routeAmountTooLargeGeneric;

  /// No description provided for @routeAmountLiquidity.
  ///
  /// In en, this message translates to:
  /// **'This amount is more than the route can take right now. Try a smaller amount.'**
  String get routeAmountLiquidity;

  /// No description provided for @settlementExpiredNothingSent.
  ///
  /// In en, this message translates to:
  /// **'This price expired before anything was sent. Nothing left your account.'**
  String get settlementExpiredNothingSent;

  /// No description provided for @settlementLedgerExpiredDuringApproval.
  ///
  /// In en, this message translates to:
  /// **'The price expired while you approved on your Ledger. Nothing was sent. Review the new price and approve again.'**
  String get settlementLedgerExpiredDuringApproval;

  /// No description provided for @settlementRegistering.
  ///
  /// In en, this message translates to:
  /// **'Sent. Registering your transfer.'**
  String get settlementRegistering;

  /// No description provided for @settlementFundingUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm whether your transfer left. We\'re checking and won\'t send it again.'**
  String get settlementFundingUnknownBody;

  /// The withdrawal reached the relayer and has a transaction, but has not confirmed yet. Distinct from an outcome nobody can account for.
  ///
  /// In en, this message translates to:
  /// **'Your withdrawal was sent and is still settling. We are tracking it and will not send it again.'**
  String get withdrawalStillSettlingBody;

  /// A new withdrawal was refused because a previous one has not resolved. Nothing was sent this time.
  ///
  /// In en, this message translates to:
  /// **'An earlier withdrawal is still settling, so nothing new was sent. Try again once it is done.'**
  String get withdrawalEarlierStillSettlingBody;

  /// No description provided for @settlementBlockedPending.
  ///
  /// In en, this message translates to:
  /// **'A previous transfer on this route is still being checked. Try again once it\'s resolved.'**
  String get settlementBlockedPending;

  /// No description provided for @settlementQuoteChangedConfirmAgain.
  ///
  /// In en, this message translates to:
  /// **'The price changed before anything was sent. Nothing left your account. Confirm again to continue.'**
  String get settlementQuoteChangedConfirmAgain;

  /// No description provided for @ledgerFundInvestingTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Bitcoin to Investing'**
  String get ledgerFundInvestingTitle;

  /// No description provided for @ledgerFundInvestingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From your Ledger'**
  String get ledgerFundInvestingSubtitle;

  /// No description provided for @ledgerFundExplainConfirmations.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger will ask you to confirm {count} times: first the refund address, then the Bitcoin transaction.'**
  String ledgerFundExplainConfirmations(int count);

  /// No description provided for @ledgerFundExplainUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The funds cannot be used until the Bitcoin network confirms the transaction. This can take an hour or more.'**
  String get ledgerFundExplainUnavailable;

  /// No description provided for @ledgerFundAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount to send'**
  String get ledgerFundAmountLabel;

  /// No description provided for @ledgerFundConnectCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to invest'**
  String get ledgerFundConnectCta;

  /// No description provided for @ledgerFundApproveCta.
  ///
  /// In en, this message translates to:
  /// **'Approve on Ledger'**
  String get ledgerFundApproveCta;

  /// No description provided for @ledgerFundStepConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect your Ledger and open the Bitcoin app'**
  String get ledgerFundStepConnect;

  /// No description provided for @ledgerFundStepConfirmRefund.
  ///
  /// In en, this message translates to:
  /// **'Check the refund address on your Ledger and approve it'**
  String get ledgerFundStepConfirmRefund;

  /// No description provided for @ledgerFundStepQuote.
  ///
  /// In en, this message translates to:
  /// **'Getting a price'**
  String get ledgerFundStepQuote;

  /// No description provided for @ledgerFundStepPrepare.
  ///
  /// In en, this message translates to:
  /// **'Preparing the transaction'**
  String get ledgerFundStepPrepare;

  /// No description provided for @ledgerFundStepSign.
  ///
  /// In en, this message translates to:
  /// **'Check the amount and address on your Ledger and approve'**
  String get ledgerFundStepSign;

  /// No description provided for @ledgerFundStepBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Sending to the Bitcoin network'**
  String get ledgerFundStepBroadcast;

  /// No description provided for @ledgerFundReviewRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund address'**
  String get ledgerFundReviewRefund;

  /// No description provided for @ledgerFundReviewExpires.
  ///
  /// In en, this message translates to:
  /// **'Price valid for'**
  String get ledgerFundReviewExpires;

  /// No description provided for @ledgerFundReviewSecondsLeft.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String ledgerFundReviewSecondsLeft(int seconds);

  /// No description provided for @ledgerFundReviewDeviceNote.
  ///
  /// In en, this message translates to:
  /// **'Check that the address and amount on your Ledger match this screen before you approve.'**
  String get ledgerFundReviewDeviceNote;

  /// No description provided for @ledgerFundSentMessage.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin sent'**
  String get ledgerFundSentMessage;

  /// No description provided for @ledgerFundSentDetail.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmations.'**
  String get ledgerFundSentDetail;

  /// No description provided for @ledgerFundInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get ledgerFundInvalidAmount;

  /// No description provided for @ledgerFundGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Nothing was sent. Try again.'**
  String get ledgerFundGenericError;

  /// No description provided for @ledgerFundQuoteFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not get a price. Nothing was sent. Try again.'**
  String get ledgerFundQuoteFailed;

  /// No description provided for @ledgerFundBuildFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not prepare this transaction. Nothing was sent.'**
  String get ledgerFundBuildFailed;

  /// No description provided for @ledgerFundSignedTxMismatch.
  ///
  /// In en, this message translates to:
  /// **'The signed transaction does not match what you reviewed. Nothing was sent.'**
  String get ledgerFundSignedTxMismatch;

  /// No description provided for @ledgerFundAddressMismatch.
  ///
  /// In en, this message translates to:
  /// **'The address on your Ledger does not match this account. Nothing was sent.'**
  String get ledgerFundAddressMismatch;

  /// No description provided for @ledgerFundFingerprintMissing.
  ///
  /// In en, this message translates to:
  /// **'Import this Ledger again before moving funds with it.'**
  String get ledgerFundFingerprintMissing;

  /// No description provided for @ledgerFundRouteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This transfer is not available right now. Nothing was sent.'**
  String get ledgerFundRouteUnavailable;

  /// No description provided for @ledgerFundOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'We could not confirm whether this was sent. Check your Ledger account before trying again.'**
  String get ledgerFundOutcomeUnknown;

  /// No description provided for @ledgerWithdrawInvestingTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw to Ledger Bitcoin'**
  String get ledgerWithdrawInvestingTitle;

  /// No description provided for @ledgerWithdrawNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals to your Ledger are not available yet.'**
  String get ledgerWithdrawNotAvailableYet;

  /// No description provided for @ledgerWithdrawAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount to withdraw'**
  String get ledgerWithdrawAmountLabel;

  /// No description provided for @ledgerWithdrawBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your balance could not load.'**
  String get ledgerWithdrawBalanceUnavailable;

  /// No description provided for @ledgerWithdrawExceedsAvailable.
  ///
  /// In en, this message translates to:
  /// **'This is more than you have available.'**
  String get ledgerWithdrawExceedsAvailable;

  /// No description provided for @ledgerWithdrawConnectCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to withdraw'**
  String get ledgerWithdrawConnectCta;

  /// No description provided for @ledgerWithdrawStepConfirmRecipient.
  ///
  /// In en, this message translates to:
  /// **'Check the receiving address on your Ledger and approve it'**
  String get ledgerWithdrawStepConfirmRecipient;

  /// No description provided for @ledgerWithdrawStepSend.
  ///
  /// In en, this message translates to:
  /// **'Approve the transfer on your Ledger'**
  String get ledgerWithdrawStepSend;

  /// No description provided for @ledgerWithdrawReviewSend.
  ///
  /// In en, this message translates to:
  /// **'You withdraw'**
  String get ledgerWithdrawReviewSend;

  /// No description provided for @ledgerWithdrawReviewReceive.
  ///
  /// In en, this message translates to:
  /// **'You receive about'**
  String get ledgerWithdrawReviewReceive;

  /// No description provided for @ledgerWithdrawReviewTo.
  ///
  /// In en, this message translates to:
  /// **'To your Ledger'**
  String get ledgerWithdrawReviewTo;

  /// No description provided for @ledgerWithdrawSentMessage.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal sent'**
  String get ledgerWithdrawSentMessage;

  /// No description provided for @ledgerPmFundExplainerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add bitcoin to Predictions'**
  String get ledgerPmFundExplainerTitle;

  /// No description provided for @ledgerPmFundExplainerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start, here is how this works with your Ledger.'**
  String get ledgerPmFundExplainerSubtitle;

  /// No description provided for @ledgerPmFundApprovalsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 approval on your Ledger} other{{count} approvals on your Ledger}}'**
  String ledgerPmFundApprovalsTitle(int count);

  /// No description provided for @ledgerPmFundApprovalsBody.
  ///
  /// In en, this message translates to:
  /// **'First you approve the bitcoin transaction. After it arrives, you approve once more to make the funds available.'**
  String get ledgerPmFundApprovalsBody;

  /// No description provided for @ledgerPmFundConfirmationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin needs confirmations'**
  String get ledgerPmFundConfirmationsTitle;

  /// No description provided for @ledgerPmFundConfirmationsBody.
  ///
  /// In en, this message translates to:
  /// **'Your bitcoin arrives after the network confirms it. This usually takes 10 to 60 minutes.'**
  String get ledgerPmFundConfirmationsBody;

  /// No description provided for @ledgerPmFundUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Funds are not usable right away'**
  String get ledgerPmFundUnavailableTitle;

  /// No description provided for @ledgerPmFundUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Until you make them available on your Ledger, the funds cannot be used for predictions.'**
  String get ledgerPmFundUnavailableBody;

  /// No description provided for @ledgerPmDeployConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Create my predictions account'**
  String get ledgerPmDeployConfirmLabel;

  /// No description provided for @ledgerPmDeployConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This Ledger has no predictions account yet. Kute creates one linked to your Ledger. No approval or fee is needed.'**
  String get ledgerPmDeployConfirmBody;

  /// No description provided for @ledgerPmDeployConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Tick the box above to continue.'**
  String get ledgerPmDeployConfirmHint;

  /// No description provided for @ledgerPmExplainerContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get ledgerPmExplainerContinue;

  /// No description provided for @ledgerPmWithdrawExplainerTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw to your Ledger'**
  String get ledgerPmWithdrawExplainerTitle;

  /// No description provided for @ledgerPmWithdrawExplainerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your available cash is converted to bitcoin and sent to a Ledger address you confirm on the device.'**
  String get ledgerPmWithdrawExplainerSubtitle;

  /// No description provided for @ledgerPmWithdrawUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals to your Ledger are not available yet.'**
  String get ledgerPmWithdrawUnavailable;

  /// No description provided for @ledgerPmWithdrawPositionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Open predictions stay put'**
  String get ledgerPmWithdrawPositionsTitle;

  /// No description provided for @ledgerPmWithdrawPositionsBody.
  ///
  /// In en, this message translates to:
  /// **'Only available cash can be withdrawn. Sell or claim a prediction first to include it.'**
  String get ledgerPmWithdrawPositionsBody;

  /// No description provided for @ledgerPmWithdrawPositionsOpenBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 open prediction. It cannot be withdrawn. Sell or claim it first.} other{You have {count} open predictions. They cannot be withdrawn. Sell or claim them first.}}'**
  String ledgerPmWithdrawPositionsOpenBody(int count);

  /// No description provided for @ledgerPmWithdrawApprovalsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 approval on your Ledger} other{{count} approvals on your Ledger}}'**
  String ledgerPmWithdrawApprovalsTitle(int count);

  /// No description provided for @ledgerPmWithdrawApprovalsBody.
  ///
  /// In en, this message translates to:
  /// **'If part of your cash is in use for predictions, you first approve releasing it. Then you approve the transfer.'**
  String get ledgerPmWithdrawApprovalsBody;

  /// No description provided for @ledgerPmWithdrawOpaqueTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger shows a code'**
  String get ledgerPmWithdrawOpaqueTitle;

  /// No description provided for @ledgerPmWithdrawArrivalTitle.
  ///
  /// In en, this message translates to:
  /// **'Arrives after confirmations'**
  String get ledgerPmWithdrawArrivalTitle;

  /// No description provided for @ledgerPmFundSentHeadline.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin sent'**
  String get ledgerPmFundSentHeadline;

  /// No description provided for @ledgerPmFundSentDetail.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmations.'**
  String get ledgerPmFundSentDetail;

  /// No description provided for @ledgerPmFundsAvailableHeadline.
  ///
  /// In en, this message translates to:
  /// **'Conversion submitted'**
  String get ledgerPmFundsAvailableHeadline;

  /// No description provided for @ledgerPmFundsAvailableDetail.
  ///
  /// In en, this message translates to:
  /// **'Your funds are available after the network confirms.'**
  String get ledgerPmFundsAvailableDetail;

  /// No description provided for @ledgerPmWithdrawSentHeadline.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal sent'**
  String get ledgerPmWithdrawSentHeadline;

  /// No description provided for @ledgerPmWithdrawSentDetail.
  ///
  /// In en, this message translates to:
  /// **'Arrives after Orchestra and the network confirm.'**
  String get ledgerPmWithdrawSentDetail;

  /// No description provided for @ledgerPmFundSheetConfirmations.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger asks you to approve twice now: the refund address, then the bitcoin transaction. After the bitcoin arrives, you approve once more to make the funds available.'**
  String get ledgerPmFundSheetConfirmations;

  /// No description provided for @ledgerPmFundSheetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The funds cannot be used for predictions until the bitcoin confirms and you make them available.'**
  String get ledgerPmFundSheetUnavailable;

  /// No description provided for @ledgerPmFundSheetDeploy.
  ///
  /// In en, this message translates to:
  /// **'Your predictions account is created first. No approval or fee is needed.'**
  String get ledgerPmFundSheetDeploy;

  /// No description provided for @ledgerPmFundConnectCta.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to continue'**
  String get ledgerPmFundConnectCta;

  /// No description provided for @ledgerPmFundStepPlan.
  ///
  /// In en, this message translates to:
  /// **'Checking your predictions account'**
  String get ledgerPmFundStepPlan;

  /// No description provided for @ledgerPmFundStepQuote.
  ///
  /// In en, this message translates to:
  /// **'Check the refund address on your Ledger and approve it. We then get a price.'**
  String get ledgerPmFundStepQuote;

  /// No description provided for @ledgerPmFundReviewAccount.
  ///
  /// In en, this message translates to:
  /// **'Predictions account'**
  String get ledgerPmFundReviewAccount;

  /// No description provided for @ledgerPmFundReviewNextStep.
  ///
  /// In en, this message translates to:
  /// **'After the bitcoin arrives, make the funds available in Predictions with one more Ledger approval.'**
  String get ledgerPmFundReviewNextStep;

  /// No description provided for @ledgerPmFundErrorAccountUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This predictions account cannot receive funds from your Ledger. Nothing was sent.'**
  String get ledgerPmFundErrorAccountUnsupported;

  /// No description provided for @ledgerPmFundErrorDeployNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm creating your predictions account first. Nothing was sent.'**
  String get ledgerPmFundErrorDeployNotConfirmed;

  /// No description provided for @ledgerPmFundErrorAccountPending.
  ///
  /// In en, this message translates to:
  /// **'Your predictions account is still being created. Try again in a minute. Nothing was sent.'**
  String get ledgerPmFundErrorAccountPending;

  /// No description provided for @ledgerPmFundErrorAddressNotOwned.
  ///
  /// In en, this message translates to:
  /// **'An address did not match this Ledger. Nothing was sent.'**
  String get ledgerPmFundErrorAddressNotOwned;

  /// No description provided for @ledgerPmFundErrorBalanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'We could not read your predictions account. Nothing was sent. Try again.'**
  String get ledgerPmFundErrorBalanceUnknown;

  /// No description provided for @ledgerPmMakeAvailableCta.
  ///
  /// In en, this message translates to:
  /// **'Make funds available'**
  String get ledgerPmMakeAvailableCta;

  /// No description provided for @ledgerPmMakeAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Make funds available'**
  String get ledgerPmMakeAvailableTitle;

  /// No description provided for @ledgerPmMakeAvailableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the funds that arrived for predictions'**
  String get ledgerPmMakeAvailableSubtitle;

  /// No description provided for @ledgerPmMakeAvailableTabNote.
  ///
  /// In en, this message translates to:
  /// **'Some funds arrived and are not usable for predictions yet.'**
  String get ledgerPmMakeAvailableTabNote;

  /// No description provided for @ledgerPmMakeAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'Your bitcoin arrived in your predictions account. One more step converts it into the cash predictions use.'**
  String get ledgerPmMakeAvailableBody;

  /// No description provided for @ledgerPmMakeAvailableApproval.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger asks you to approve once. It shows a code, not the details, so check the amount here first.'**
  String get ledgerPmMakeAvailableApproval;

  /// No description provided for @ledgerPmMakeAvailableAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount to make available'**
  String get ledgerPmMakeAvailableAmountLabel;

  /// No description provided for @ledgerPmMakeAvailableNothing.
  ///
  /// In en, this message translates to:
  /// **'No arrived funds are waiting to be made available.'**
  String get ledgerPmMakeAvailableNothing;

  /// No description provided for @ledgerPmMakeAvailablePending.
  ///
  /// In en, this message translates to:
  /// **'We are still checking this conversion. You do not need to approve it again.'**
  String get ledgerPmMakeAvailablePending;

  /// No description provided for @settlementOpenLedgerAccount.
  ///
  /// In en, this message translates to:
  /// **'Open Ledger account'**
  String get settlementOpenLedgerAccount;

  /// No description provided for @routePausedBody.
  ///
  /// In en, this message translates to:
  /// **'This action is paused for now. Your balances and pending transfers are not affected.'**
  String get routePausedBody;

  /// No description provided for @stepUpBiometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Face ID isn\'t available right now. Enter your Kute PIN to continue.'**
  String get stepUpBiometricUnavailable;

  /// No description provided for @stepUpBiometricUnavailableAndroid.
  ///
  /// In en, this message translates to:
  /// **'Your fingerprint isn\'t available right now. Enter your Kute PIN to continue.'**
  String get stepUpBiometricUnavailableAndroid;

  /// No description provided for @stepUpBiometricChanged.
  ///
  /// In en, this message translates to:
  /// **'Face ID changed on this phone. Enter your Kute PIN to continue.'**
  String get stepUpBiometricChanged;

  /// No description provided for @stepUpDetailsChanged.
  ///
  /// In en, this message translates to:
  /// **'The amount, price or destination changed after you confirmed. Check the details and confirm again.'**
  String get stepUpDetailsChanged;

  /// No description provided for @stepUpReviewAgain.
  ///
  /// In en, this message translates to:
  /// **'Review again'**
  String get stepUpReviewAgain;

  /// No description provided for @stepUpReasonSend.
  ///
  /// In en, this message translates to:
  /// **'Confirm sending {amount}'**
  String stepUpReasonSend(String amount);

  /// No description provided for @stepUpReasonBet.
  ///
  /// In en, this message translates to:
  /// **'Confirm a {amount} prediction'**
  String stepUpReasonBet(String amount);

  /// No description provided for @stepUpReasonSell.
  ///
  /// In en, this message translates to:
  /// **'Confirm selling your position'**
  String get stepUpReasonSell;

  /// No description provided for @stepUpReasonOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm your {market} order'**
  String stepUpReasonOrder(String market);

  /// No description provided for @stepUpReasonDeposit.
  ///
  /// In en, this message translates to:
  /// **'Confirm your deposit of {amount}'**
  String stepUpReasonDeposit(String amount);

  /// No description provided for @stepUpReasonWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Confirm your withdrawal of {amount}'**
  String stepUpReasonWithdraw(String amount);

  /// No description provided for @stepUpReasonRevealSeed.
  ///
  /// In en, this message translates to:
  /// **'Show your recovery phrase'**
  String get stepUpReasonRevealSeed;

  /// No description provided for @stepUpReasonRefund.
  ///
  /// In en, this message translates to:
  /// **'Confirm your refund'**
  String get stepUpReasonRefund;

  /// No description provided for @stepUpReasonSwitchWallet.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String stepUpReasonSwitchWallet(String name);

  /// No description provided for @stepUpReasonRemoveWallet.
  ///
  /// In en, this message translates to:
  /// **'Remove this wallet'**
  String get stepUpReasonRemoveWallet;

  /// No description provided for @stepUpReasonBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Change biometric unlock'**
  String get stepUpReasonBiometrics;

  /// No description provided for @removeWalletNotBackedUpTitle.
  ///
  /// In en, this message translates to:
  /// **'This wallet isn\'t backed up'**
  String get removeWalletNotBackedUpTitle;

  /// No description provided for @removeWalletNotBackedUpBody.
  ///
  /// In en, this message translates to:
  /// **'If you remove it without your 12 words, you can\'t get it back.'**
  String get removeWalletNotBackedUpBody;

  /// No description provided for @removeWalletBackUpFirst.
  ///
  /// In en, this message translates to:
  /// **'Back up first'**
  String get removeWalletBackUpFirst;

  /// No description provided for @removeWalletAnyway.
  ///
  /// In en, this message translates to:
  /// **'Remove anyway'**
  String get removeWalletAnyway;

  /// No description provided for @pendingIntentExpired.
  ///
  /// In en, this message translates to:
  /// **'Your queued order expired. Confirm it again to place it.'**
  String get pendingIntentExpired;

  /// Step-up prompt reason for placing a Hyperliquid portfolio Builder run with one approval.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Confirm your portfolio order} other{Confirm your {count} portfolio orders}}'**
  String stepUpReasonBuilderOrders(int count);

  /// Portfolio Builder leg row when the one-time approval for the run expired before this leg was placed.
  ///
  /// In en, this message translates to:
  /// **'Your approval expired. Place this order again.'**
  String get builderLegApprovalExpired;

  /// Predictions bet, sell or withdrawal stopped because its one-time approval expired or was already used before anything was sent.
  ///
  /// In en, this message translates to:
  /// **'Your approval expired. Confirm again to continue.'**
  String get stepUpApprovalExpired;

  /// No description provided for @feeUiEstimatedFee.
  ///
  /// In en, this message translates to:
  /// **'Estimated fee'**
  String get feeUiEstimatedFee;

  /// No description provided for @feeUiYouReceiveAtLeast.
  ///
  /// In en, this message translates to:
  /// **'You receive at least'**
  String get feeUiYouReceiveAtLeast;

  /// No description provided for @feeUiShownBeforeYouConfirm.
  ///
  /// In en, this message translates to:
  /// **'Shown before you confirm'**
  String get feeUiShownBeforeYouConfirm;

  /// No description provided for @feeUiIncludedInTheAmountYouReceive.
  ///
  /// In en, this message translates to:
  /// **'Included in the amount you receive'**
  String get feeUiIncludedInTheAmountYouReceive;

  /// No description provided for @feeUiEstimateExactFeesShownBeforeYouConfirm.
  ///
  /// In en, this message translates to:
  /// **'Estimate. The exact fees are shown before you confirm.'**
  String get feeUiEstimateExactFeesShownBeforeYouConfirm;

  /// No description provided for @feeUiTakenFromTheAmountYouSend.
  ///
  /// In en, this message translates to:
  /// **'Taken from the amount you send.'**
  String get feeUiTakenFromTheAmountYouSend;

  /// Fee row label with the Kute rate, for example 0.50%.
  ///
  /// In en, this message translates to:
  /// **'Kute fee ({rate})'**
  String feeUiKuteFeeWithRate(String rate);

  /// One line beside a reusable deposit address: the Kute fee rate (for example 0.50%) that is taken from what arrives at it.
  ///
  /// In en, this message translates to:
  /// **'Kute fee {rate} · taken from what arrives'**
  String receiveKuteFeeOnArrival(String rate);

  /// No description provided for @feeUiFriendDiscountIncluded.
  ///
  /// In en, this message translates to:
  /// **'Includes your {discount} friend discount.'**
  String feeUiFriendDiscountIncluded(String discount);

  /// No description provided for @feeUiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get feeUiUnavailable;

  /// No description provided for @feeUiEnterAnAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get feeUiEnterAnAmount;

  /// No description provided for @feeUiCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get feeUiCalculating;

  /// No description provided for @feeUiUnavailableRetry.
  ///
  /// In en, this message translates to:
  /// **'Unavailable · Retry'**
  String get feeUiUnavailableRetry;

  /// No description provided for @feeUiTotalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Total unavailable'**
  String get feeUiTotalUnavailable;

  /// No description provided for @feeUiExchangeFeeEstimate.
  ///
  /// In en, this message translates to:
  /// **'Exchange fee estimate'**
  String get feeUiExchangeFeeEstimate;

  /// No description provided for @feeUiKuteFee.
  ///
  /// In en, this message translates to:
  /// **'Kute fee'**
  String get feeUiKuteFee;

  /// No description provided for @feeUiPolymarketFee.
  ///
  /// In en, this message translates to:
  /// **'Polymarket fee'**
  String get feeUiPolymarketFee;

  /// No description provided for @feeUiEstimatedProceedsAfterFees.
  ///
  /// In en, this message translates to:
  /// **'Estimated proceeds after fees'**
  String get feeUiEstimatedProceedsAfterFees;

  /// No description provided for @feeUiConversionFeeEstimate.
  ///
  /// In en, this message translates to:
  /// **'Conversion fee estimate'**
  String get feeUiConversionFeeEstimate;

  /// No description provided for @feeUiBridgeWithdrawalFee.
  ///
  /// In en, this message translates to:
  /// **'Bridge withdrawal fee'**
  String get feeUiBridgeWithdrawalFee;

  /// No description provided for @feeUiNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get feeUiNetworkFee;

  /// No description provided for @feeUiBitcoinNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin network fee'**
  String get feeUiBitcoinNetworkFee;

  /// No description provided for @feeUiShownOnLedgerBeforeSigning.
  ///
  /// In en, this message translates to:
  /// **'Shown on Ledger before signing'**
  String get feeUiShownOnLedgerBeforeSigning;

  /// No description provided for @feeUiCoveredByRelayer.
  ///
  /// In en, this message translates to:
  /// **'Covered by relayer'**
  String get feeUiCoveredByRelayer;

  /// No description provided for @feeUiPaidFee.
  ///
  /// In en, this message translates to:
  /// **'Paid fee'**
  String get feeUiPaidFee;

  /// No description provided for @feeUiFeeRebate.
  ///
  /// In en, this message translates to:
  /// **'Fee rebate'**
  String get feeUiFeeRebate;

  /// No description provided for @feeUiPaidTradingFee.
  ///
  /// In en, this message translates to:
  /// **'Paid trading fee'**
  String get feeUiPaidTradingFee;

  /// No description provided for @feeUiNotReportedInActivity.
  ///
  /// In en, this message translates to:
  /// **'Not reported in activity'**
  String get feeUiNotReportedInActivity;

  /// No description provided for @feeUiProviderQuote.
  ///
  /// In en, this message translates to:
  /// **'Provider quote'**
  String get feeUiProviderQuote;

  /// No description provided for @feeUiEntryHistoryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Entry history unavailable'**
  String get feeUiEntryHistoryUnavailable;

  /// No description provided for @feeUiEntryCapitalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Entry capital unavailable'**
  String get feeUiEntryCapitalUnavailable;

  /// No description provided for @feeUiAvailableAfterSelling.
  ///
  /// In en, this message translates to:
  /// **'Available after selling'**
  String get feeUiAvailableAfterSelling;

  /// No description provided for @feeUiVsHoldingBitcoin.
  ///
  /// In en, this message translates to:
  /// **'vs holding Bitcoin'**
  String get feeUiVsHoldingBitcoin;

  /// No description provided for @feeUiPositionVsHoldingBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Position vs holding Bitcoin'**
  String get feeUiPositionVsHoldingBitcoin;

  /// No description provided for @feeUiEstimatedDailyBitcoinPricesBeforeFees.
  ///
  /// In en, this message translates to:
  /// **'Estimated · daily Bitcoin prices · before fees'**
  String get feeUiEstimatedDailyBitcoinPricesBeforeFees;

  /// No description provided for @feeUiCurrentPositionDailyEntryBitcoinPricesBeforeFees.
  ///
  /// In en, this message translates to:
  /// **'Current position · daily entry Bitcoin prices · before fees'**
  String get feeUiCurrentPositionDailyEntryBitcoinPricesBeforeFees;

  /// No description provided for @feeUiAheadOfHoldingBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Ahead of holding Bitcoin.'**
  String get feeUiAheadOfHoldingBitcoin;

  /// No description provided for @feeUiBehindHoldingBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Behind holding Bitcoin.'**
  String get feeUiBehindHoldingBitcoin;

  /// No description provided for @feeUiIncludedInTheConversionNetworkFeesAndExchangeRateSpreadMayAlsoApply.
  ///
  /// In en, this message translates to:
  /// **'Included in the conversion. Network fees and exchange-rate spread may also apply.'**
  String
      get feeUiIncludedInTheConversionNetworkFeesAndExchangeRateSpreadMayAlsoApply;

  /// No description provided for @feeUiIfFilledAsATakerMakerFeesMayBeLower.
  ///
  /// In en, this message translates to:
  /// **'If filled as a taker. Maker fees may be lower.'**
  String get feeUiIfFilledAsATakerMakerFeesMayBeLower;

  /// No description provided for @feeUiFinalFeeDependsOnTheFillPrice.
  ///
  /// In en, this message translates to:
  /// **'Final fee depends on the fill price.'**
  String get feeUiFinalFeeDependsOnTheFillPrice;

  /// No description provided for @feeUiOnFilledTradeValueFinalFeesMayVaryRebatesAreNotDeducted.
  ///
  /// In en, this message translates to:
  /// **'On filled trade value. Final fees may vary; rebates are not deducted.'**
  String get feeUiOnFilledTradeValueFinalFeesMayVaryRebatesAreNotDeducted;

  /// No description provided for @feeUiVenueFeeVariesByMarketKuteFeeShownBelow.
  ///
  /// In en, this message translates to:
  /// **'Venue fee varies by market. Kute fee shown below.'**
  String get feeUiVenueFeeVariesByMarketKuteFeeShownBelow;

  /// No description provided for @feeUiIncludesAnyKuteBuilderFee.
  ///
  /// In en, this message translates to:
  /// **'Includes any Kute builder fee.'**
  String get feeUiIncludesAnyKuteBuilderFee;

  /// No description provided for @feeUiTransferFee.
  ///
  /// In en, this message translates to:
  /// **'Transfer fee'**
  String get feeUiTransferFee;

  /// No description provided for @feeUiNotQuotedByVenue.
  ///
  /// In en, this message translates to:
  /// **'Not quoted by venue'**
  String get feeUiNotQuotedByVenue;

  /// No description provided for @coinLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Give this a name'**
  String get coinLabelHint;

  /// No description provided for @coinBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get coinBlockHeight;

  /// No description provided for @coinsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Coins show up here once this wallet has synced.'**
  String get coinsEmptyHint;

  /// No description provided for @coinLabelsLocal.
  ///
  /// In en, this message translates to:
  /// **'Labels stay on this device. Your recovery phrase does not restore them.'**
  String get coinLabelsLocal;

  /// No description provided for @coinLabelInheritedHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the transaction label.'**
  String get coinLabelInheritedHint;

  /// No description provided for @coinLabelSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the label. Please try again.'**
  String get coinLabelSaveFailed;

  /// No description provided for @coinAddTransactionLabel.
  ///
  /// In en, this message translates to:
  /// **'Label transaction'**
  String get coinAddTransactionLabel;

  /// No description provided for @coinTransactionLabel.
  ///
  /// In en, this message translates to:
  /// **'Transaction label'**
  String get coinTransactionLabel;

  /// No description provided for @coinDetails.
  ///
  /// In en, this message translates to:
  /// **'Coin details'**
  String get coinDetails;

  /// No description provided for @coinAddLabel.
  ///
  /// In en, this message translates to:
  /// **'Label coin'**
  String get coinAddLabel;

  /// No description provided for @coinLabel.
  ///
  /// In en, this message translates to:
  /// **'Coin label'**
  String get coinLabel;

  /// No description provided for @coinOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get coinOutput;

  /// No description provided for @coinSelection.
  ///
  /// In en, this message translates to:
  /// **'Coin selection'**
  String get coinSelection;

  /// No description provided for @coinSelectionAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get coinSelectionAutomatic;

  /// No description provided for @coinSelectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the coins to spend. Leave all unselected for automatic selection.'**
  String get coinSelectionHelp;

  /// No description provided for @coinSelectionInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Selected coins must cover the payment and network fee.'**
  String get coinSelectionInsufficient;

  /// No description provided for @feeUiAddFundsToContinue.
  ///
  /// In en, this message translates to:
  /// **'Add funds to continue'**
  String get feeUiAddFundsToContinue;

  /// No description provided for @feeUiPriceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get feeUiPriceUnavailable;

  /// No description provided for @feeUiEstimateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Estimate unavailable'**
  String get feeUiEstimateUnavailable;

  /// No description provided for @feeUiVariesByMarket.
  ///
  /// In en, this message translates to:
  /// **'Varies by market'**
  String get feeUiVariesByMarket;

  /// No description provided for @feeUiAvailableAfterAccountSetup.
  ///
  /// In en, this message translates to:
  /// **'Available after account setup'**
  String get feeUiAvailableAfterAccountSetup;

  /// No description provided for @feeUiChooseALargerAmount.
  ///
  /// In en, this message translates to:
  /// **'Choose a larger amount'**
  String get feeUiChooseALargerAmount;

  /// No description provided for @feeUiShownInCashApp.
  ///
  /// In en, this message translates to:
  /// **'Shown in Cash App'**
  String get feeUiShownInCashApp;

  /// No description provided for @feeUiInsufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get feeUiInsufficientBalance;

  /// No description provided for @feeUiUpdatingBalance.
  ///
  /// In en, this message translates to:
  /// **'Updating balance'**
  String get feeUiUpdatingBalance;

  /// No description provided for @feeUiBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Balance unavailable'**
  String get feeUiBalanceUnavailable;

  /// No description provided for @walletImportedConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Wallet imported'**
  String get walletImportedConfirmation;

  /// No description provided for @errorCopyGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorCopyGeneric;

  /// No description provided for @errorCopyOffline.
  ///
  /// In en, this message translates to:
  /// **'You seem to be offline. Check your connection and try again.'**
  String get errorCopyOffline;

  /// No description provided for @errorCopyTimeout.
  ///
  /// In en, this message translates to:
  /// **'That took too long. Please try again.'**
  String get errorCopyTimeout;

  /// No description provided for @errorCopyLocked.
  ///
  /// In en, this message translates to:
  /// **'Unlock Kute first, then try again.'**
  String get errorCopyLocked;

  /// No description provided for @errorCopyBusy.
  ///
  /// In en, this message translates to:
  /// **'Your wallet is still syncing. Try again in a moment.'**
  String get errorCopyBusy;

  /// No description provided for @errorCopyInsufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'Not enough funds to cover this amount and the network fee.'**
  String get errorCopyInsufficientFunds;

  /// No description provided for @errorCopyInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Check what you entered and try again.'**
  String get errorCopyInvalidInput;

  /// No description provided for @sendAmountUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Amount in'**
  String get sendAmountUnitTitle;

  /// No description provided for @sendAmountUnitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the unit you want to type the amount in.'**
  String get sendAmountUnitSubtitle;

  /// No description provided for @sendUnitSats.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin, in sats'**
  String get sendUnitSats;

  /// No description provided for @sendUnitBtc.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin'**
  String get sendUnitBtc;

  /// No description provided for @currencyNameUsd.
  ///
  /// In en, this message translates to:
  /// **'US dollar'**
  String get currencyNameUsd;

  /// No description provided for @currencyNameEur.
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyNameEur;

  /// No description provided for @currencyNameBrl.
  ///
  /// In en, this message translates to:
  /// **'Brazilian real'**
  String get currencyNameBrl;

  /// No description provided for @currencyNameGbp.
  ///
  /// In en, this message translates to:
  /// **'British pound'**
  String get currencyNameGbp;

  /// No description provided for @currencyNameChf.
  ///
  /// In en, this message translates to:
  /// **'Swiss franc'**
  String get currencyNameChf;

  /// No description provided for @chartToolTrendLine.
  ///
  /// In en, this message translates to:
  /// **'Trend line'**
  String get chartToolTrendLine;

  /// No description provided for @chartToolLevel.
  ///
  /// In en, this message translates to:
  /// **'Horizontal level'**
  String get chartToolLevel;

  /// No description provided for @chartToolRay.
  ///
  /// In en, this message translates to:
  /// **'Ray'**
  String get chartToolRay;

  /// No description provided for @chartToolRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get chartToolRectangle;

  /// No description provided for @chartToolFibonacci.
  ///
  /// In en, this message translates to:
  /// **'Fibonacci retracement'**
  String get chartToolFibonacci;

  /// No description provided for @chartToolText.
  ///
  /// In en, this message translates to:
  /// **'Text note'**
  String get chartToolText;

  /// No description provided for @chartToolHorizontalRay.
  ///
  /// In en, this message translates to:
  /// **'Horizontal ray'**
  String get chartToolHorizontalRay;

  /// No description provided for @chartToolVerticalLine.
  ///
  /// In en, this message translates to:
  /// **'Vertical line'**
  String get chartToolVerticalLine;

  /// No description provided for @chartToolExtendedLine.
  ///
  /// In en, this message translates to:
  /// **'Extended line'**
  String get chartToolExtendedLine;

  /// No description provided for @chartToolParallelChannel.
  ///
  /// In en, this message translates to:
  /// **'Parallel channel'**
  String get chartToolParallelChannel;

  /// No description provided for @chartToolLongPosition.
  ///
  /// In en, this message translates to:
  /// **'Long position'**
  String get chartToolLongPosition;

  /// No description provided for @chartToolShortPosition.
  ///
  /// In en, this message translates to:
  /// **'Short position'**
  String get chartToolShortPosition;

  /// No description provided for @chartToolPriceRange.
  ///
  /// In en, this message translates to:
  /// **'Price range'**
  String get chartToolPriceRange;

  /// No description provided for @chartToolDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get chartToolDateRange;

  /// No description provided for @chartToolDateAndPriceRange.
  ///
  /// In en, this message translates to:
  /// **'Date and price range'**
  String get chartToolDateAndPriceRange;

  /// No description provided for @chartToolsButton.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get chartToolsButton;

  /// No description provided for @chartStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Chart style'**
  String get chartStyleTitle;

  /// No description provided for @chartStyleCandles.
  ///
  /// In en, this message translates to:
  /// **'Candles'**
  String get chartStyleCandles;

  /// No description provided for @chartStyleHollow.
  ///
  /// In en, this message translates to:
  /// **'Hollow candles'**
  String get chartStyleHollow;

  /// No description provided for @chartStyleBars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get chartStyleBars;

  /// No description provided for @chartStyleHeikinAshi.
  ///
  /// In en, this message translates to:
  /// **'Heikin Ashi'**
  String get chartStyleHeikinAshi;

  /// No description provided for @chartStyleLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get chartStyleLine;

  /// No description provided for @chartStyleArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get chartStyleArea;

  /// No description provided for @chartStyleBaseline.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get chartStyleBaseline;

  /// No description provided for @chartToolGroupLines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get chartToolGroupLines;

  /// No description provided for @chartToolGroupShapes.
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get chartToolGroupShapes;

  /// No description provided for @chartToolGroupPositions.
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get chartToolGroupPositions;

  /// No description provided for @chartToolGroupMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get chartToolGroupMeasure;

  /// No description provided for @chartToolGroupNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get chartToolGroupNotes;

  /// No description provided for @chartHintTapToPlace.
  ///
  /// In en, this message translates to:
  /// **'Tap the chart to place: {tool}'**
  String chartHintTapToPlace(String tool);

  /// No description provided for @chartHintDragToPlace.
  ///
  /// In en, this message translates to:
  /// **'Drag on the chart to draw: {tool}'**
  String chartHintDragToPlace(String tool);

  /// No description provided for @chartHintAdjust.
  ///
  /// In en, this message translates to:
  /// **'Drag a handle to adjust, drag the line to move it.'**
  String get chartHintAdjust;

  /// No description provided for @chartHintPickTool.
  ///
  /// In en, this message translates to:
  /// **'Pick a tool, or tap a drawing to edit it.'**
  String get chartHintPickTool;

  /// No description provided for @chartMoveOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Move order'**
  String get chartMoveOrderTitle;

  /// No description provided for @chartMoveOrderCta.
  ///
  /// In en, this message translates to:
  /// **'Move order'**
  String get chartMoveOrderCta;

  /// No description provided for @chartOrderMoved.
  ///
  /// In en, this message translates to:
  /// **'Order moved to {price}'**
  String chartOrderMoved(String price);

  /// No description provided for @chartOrderMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'The order could not be moved. It is still where it was.'**
  String get chartOrderMoveFailed;

  /// No description provided for @chartUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get chartUndo;

  /// No description provided for @chartRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get chartRedo;

  /// No description provided for @chartDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete drawing'**
  String get chartDelete;

  /// No description provided for @chartMagnet.
  ///
  /// In en, this message translates to:
  /// **'Snap to candle prices'**
  String get chartMagnet;

  /// No description provided for @chartNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note to this chart'**
  String get chartNoteHint;

  /// No description provided for @chartEditNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get chartEditNote;

  /// No description provided for @chartNeutralColor.
  ///
  /// In en, this message translates to:
  /// **'Neutral color'**
  String get chartNeutralColor;

  /// No description provided for @chartUpColor.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get chartUpColor;

  /// No description provided for @chartDownColor.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get chartDownColor;

  /// No description provided for @chartHighlightColor.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get chartHighlightColor;

  /// No description provided for @chartVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get chartVolume;

  /// No description provided for @chartLogScale.
  ///
  /// In en, this message translates to:
  /// **'Log scale'**
  String get chartLogScale;

  /// No description provided for @chartVwapWindow.
  ///
  /// In en, this message translates to:
  /// **'VWAP across the displayed candles'**
  String get chartVwapWindow;

  /// No description provided for @chartRsiLabel.
  ///
  /// In en, this message translates to:
  /// **'RSI (14)'**
  String get chartRsiLabel;

  /// No description provided for @chartIndicators.
  ///
  /// In en, this message translates to:
  /// **'Indicators'**
  String get chartIndicators;

  /// No description provided for @chartInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get chartInterval;

  /// No description provided for @chartSelectTool.
  ///
  /// In en, this message translates to:
  /// **'Select and edit drawings'**
  String get chartSelectTool;

  /// No description provided for @chartStopDrawing.
  ///
  /// In en, this message translates to:
  /// **'Stop drawing'**
  String get chartStopDrawing;

  /// No description provided for @chartRemoveAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove all drawings'**
  String get chartRemoveAllTitle;

  /// No description provided for @chartRemoveAllBody.
  ///
  /// In en, this message translates to:
  /// **'Every drawing on this chart is removed. Undo brings them back while the chart stays open.'**
  String get chartRemoveAllBody;

  /// No description provided for @chartRemoveAllCta.
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get chartRemoveAllCta;

  /// Earn and portfolio presentation copy.
  ///
  /// In en, this message translates to:
  /// **'Performance unavailable'**
  String get portfolioPerformanceUnavailable;

  /// Predictions statistics tile: realized profit or loss over the selected range (sold, claimed or resolved predictions).
  ///
  /// In en, this message translates to:
  /// **'Realized P&L'**
  String get portfolioStatRealized;

  /// Predictions statistics tile: unrealized profit or loss of the open predictions now, at live prices.
  ///
  /// In en, this message translates to:
  /// **'Open P&L'**
  String get portfolioStatOpen;

  /// Predictions statistics tile: total amount put on the predictions made in the selected range.
  ///
  /// In en, this message translates to:
  /// **'Amount predicted'**
  String get portfolioStatAmountPredicted;

  /// Predictions statistics tile: number of predictions made in the selected range.
  ///
  /// In en, this message translates to:
  /// **'Predictions'**
  String get portfolioStatCount;

  /// Earn and portfolio presentation copy.
  ///
  /// In en, this message translates to:
  /// **'{shares} shares at {price}'**
  String portfolioPredictionEntry(String shares, String price);

  /// No description provided for @ledgerBetReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review prediction'**
  String get ledgerBetReviewTitle;

  /// No description provided for @ledgerBetMaxSpend.
  ///
  /// In en, this message translates to:
  /// **'Maximum spend'**
  String get ledgerBetMaxSpend;

  /// No description provided for @ledgerBetMinShares.
  ///
  /// In en, this message translates to:
  /// **'Minimum shares before fees'**
  String get ledgerBetMinShares;

  /// No description provided for @ledgerBetWorstPrice.
  ///
  /// In en, this message translates to:
  /// **'Maximum price'**
  String get ledgerBetWorstPrice;

  /// No description provided for @ledgerBetVerifyCash.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger to verify your Predictions balance and open orders.'**
  String get ledgerBetVerifyCash;

  /// No description provided for @ledgerBetCashUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your Predictions balance and open orders could not be verified. Try again.'**
  String get ledgerBetCashUnavailable;

  /// No description provided for @ledgerBetInsufficientCash.
  ///
  /// In en, this message translates to:
  /// **'This prediction exceeds your available cash. Deposit or make arrived funds available first.'**
  String get ledgerBetInsufficientCash;

  /// No description provided for @ledgerBetPending.
  ///
  /// In en, this message translates to:
  /// **'A previous prediction is still being confirmed. Check its status before placing another.'**
  String get ledgerBetPending;

  /// No description provided for @ledgerBetSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Prediction submitted'**
  String get ledgerBetSubmitted;

  /// No description provided for @ledgerBetDetailsChanged.
  ///
  /// In en, this message translates to:
  /// **'The market or account details changed. Review the prediction again.'**
  String get ledgerBetDetailsChanged;

  /// No description provided for @ledgerBetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This Ledger account cannot place predictions yet.'**
  String get ledgerBetUnavailable;

  /// No description provided for @ledgerBetCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check prediction status'**
  String get ledgerBetCheckStatus;

  /// No description provided for @chartPriceDelayed.
  ///
  /// In en, this message translates to:
  /// **'Price delayed'**
  String get chartPriceDelayed;

  /// No description provided for @chartMaxLeverage.
  ///
  /// In en, this message translates to:
  /// **'Maximum leverage'**
  String get chartMaxLeverage;

  /// No description provided for @chartInstrument.
  ///
  /// In en, this message translates to:
  /// **'Instrument'**
  String get chartInstrument;

  /// No description provided for @chartYourInvestment.
  ///
  /// In en, this message translates to:
  /// **'Your investment'**
  String get chartYourInvestment;

  /// No description provided for @chartBoughtAt.
  ///
  /// In en, this message translates to:
  /// **'Bought at'**
  String get chartBoughtAt;

  /// No description provided for @chartSoldAt.
  ///
  /// In en, this message translates to:
  /// **'Sold at'**
  String get chartSoldAt;

  /// No description provided for @chartManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get chartManage;

  /// No description provided for @chartPositionSize.
  ///
  /// In en, this message translates to:
  /// **'Position size'**
  String get chartPositionSize;

  /// No description provided for @chartLeverage.
  ///
  /// In en, this message translates to:
  /// **'Leverage'**
  String get chartLeverage;

  /// No description provided for @chartLiquidationPrice.
  ///
  /// In en, this message translates to:
  /// **'Liquidation price'**
  String get chartLiquidationPrice;

  /// No description provided for @chartYouHold.
  ///
  /// In en, this message translates to:
  /// **'You hold'**
  String get chartYouHold;

  /// No description provided for @chartNoData.
  ///
  /// In en, this message translates to:
  /// **'No chart data'**
  String get chartNoData;

  /// No description provided for @ledgerBetPrepared.
  ///
  /// In en, this message translates to:
  /// **'Spending enabled. Review your prediction to continue.'**
  String get ledgerBetPrepared;

  /// No description provided for @moveAddPredictions.
  ///
  /// In en, this message translates to:
  /// **'Add to Predictions'**
  String get moveAddPredictions;

  /// No description provided for @moveAddInvesting.
  ///
  /// In en, this message translates to:
  /// **'Add to Investing'**
  String get moveAddInvesting;

  /// No description provided for @moveWithdrawPredictions.
  ///
  /// In en, this message translates to:
  /// **'Withdraw from Predictions'**
  String get moveWithdrawPredictions;

  /// No description provided for @moveWithdrawInvesting.
  ///
  /// In en, this message translates to:
  /// **'Withdraw from Investing'**
  String get moveWithdrawInvesting;

  /// No description provided for @moveBuyBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Buy bitcoin'**
  String get moveBuyBitcoin;

  /// The ONE label for the door that funds the dollar balance: the button on the Dollars screen, the Move sheet title, and the payment method's second line. Always shown beside the shared dollar mark.
  ///
  /// In en, this message translates to:
  /// **'Dollar deposit'**
  String get dollarDeposit;

  /// The other side of dollarDeposit: money leaving the dollar balance. Same mark.
  ///
  /// In en, this message translates to:
  /// **'Dollar withdrawal'**
  String get dollarWithdrawal;

  /// No description provided for @moveSellBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Sell bitcoin'**
  String get moveSellBitcoin;

  /// No description provided for @moveTransfer.
  ///
  /// In en, this message translates to:
  /// **'Move money'**
  String get moveTransfer;

  /// No description provided for @moveAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get moveAdd;

  /// No description provided for @moveWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get moveWithdraw;

  /// No description provided for @moveBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get moveBuy;

  /// No description provided for @moveSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get moveSell;

  /// No description provided for @moveFailure.
  ///
  /// In en, this message translates to:
  /// **'The move could not be completed. Check its status before trying again.'**
  String get moveFailure;

  /// No description provided for @moveInvestingBalance.
  ///
  /// In en, this message translates to:
  /// **'Your Investing balance'**
  String get moveInvestingBalance;

  /// No description provided for @moveAmountArrived.
  ///
  /// In en, this message translates to:
  /// **'{amount} arrived in your Spending account'**
  String moveAmountArrived(String amount);

  /// No description provided for @moveAmountSentWallet.
  ///
  /// In en, this message translates to:
  /// **'{amount} sent to {name}. Waiting for confirmation.'**
  String moveAmountSentWallet(String amount, String name);

  /// No description provided for @recoveryCandidateBalance.
  ///
  /// In en, this message translates to:
  /// **'{amount} · {count, plural, =1{1 transaction} other{{count} transactions}}'**
  String recoveryCandidateBalance(String amount, int count);

  /// No description provided for @ledgerBetEnableSpending.
  ///
  /// In en, this message translates to:
  /// **'Allow predictions spending'**
  String get ledgerBetEnableSpending;

  /// No description provided for @feeBitcoinNetwork.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin network'**
  String get feeBitcoinNetwork;

  /// No description provided for @feeLightningNetwork.
  ///
  /// In en, this message translates to:
  /// **'Lightning payment'**
  String get feeLightningNetwork;

  /// No description provided for @feePredictions.
  ///
  /// In en, this message translates to:
  /// **'Prediction trading'**
  String get feePredictions;

  /// No description provided for @feeConversion.
  ///
  /// In en, this message translates to:
  /// **'Currency conversion'**
  String get feeConversion;

  /// No description provided for @feeApp.
  ///
  /// In en, this message translates to:
  /// **'App fee'**
  String get feeApp;

  /// No description provided for @feeNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No fees in this period'**
  String get feeNoHistory;

  /// No description provided for @feeTotalPaid.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get feeTotalPaid;

  /// No description provided for @feeShareOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{share}% of total'**
  String feeShareOfTotal(String share);

  /// No description provided for @feeTransactionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction} other{{count} transactions}}'**
  String feeTransactionCount(int count);

  /// No description provided for @chartLastMinutes.
  ///
  /// In en, this message translates to:
  /// **'Last {count} minutes'**
  String chartLastMinutes(int count);

  /// No description provided for @investingMinimumOrderUnknown.
  ///
  /// In en, this message translates to:
  /// **'Below the minimum order size.'**
  String get investingMinimumOrderUnknown;

  /// No description provided for @investingMinimumOrder.
  ///
  /// In en, this message translates to:
  /// **'Minimum is {amount}.'**
  String investingMinimumOrder(String amount);

  /// No description provided for @investingMinimumScaleOrder.
  ///
  /// In en, this message translates to:
  /// **'Each order must be at least {amount}.'**
  String investingMinimumScaleOrder(String amount);

  /// No description provided for @investingFundingFromBalance.
  ///
  /// In en, this message translates to:
  /// **'{amount} will be taken from your Investing balance.'**
  String investingFundingFromBalance(String amount);

  /// No description provided for @investingThinMarket.
  ///
  /// In en, this message translates to:
  /// **'This market is thin right now. You may get a worse price than shown.'**
  String get investingThinMarket;

  /// No description provided for @investingFeeApprovalFailed.
  ///
  /// In en, this message translates to:
  /// **'Fee approval was not completed. Please try again.'**
  String get investingFeeApprovalFailed;

  /// No description provided for @investingFeeSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing fee settings could not be verified. Try again.'**
  String get investingFeeSettingsUnavailable;

  /// No description provided for @investingViewPositions.
  ///
  /// In en, this message translates to:
  /// **'View positions'**
  String get investingViewPositions;

  /// No description provided for @investingBought.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get investingBought;

  /// No description provided for @investingSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get investingSold;

  /// No description provided for @investingBalanceUpdating.
  ///
  /// In en, this message translates to:
  /// **'Your balance will update in a moment.'**
  String get investingBalanceUpdating;

  /// No description provided for @investingNoFillConfirmed.
  ///
  /// In en, this message translates to:
  /// **'No fill confirmed'**
  String get investingNoFillConfirmed;

  /// No description provided for @investingPartiallyClosed.
  ///
  /// In en, this message translates to:
  /// **'Partially closed'**
  String get investingPartiallyClosed;

  /// No description provided for @investingPositionClosed.
  ///
  /// In en, this message translates to:
  /// **'Position closed'**
  String get investingPositionClosed;

  /// No description provided for @investingAmountClosed.
  ///
  /// In en, this message translates to:
  /// **'Amount closed'**
  String get investingAmountClosed;

  /// No description provided for @investingExitPrice.
  ///
  /// In en, this message translates to:
  /// **'Exit price'**
  String get investingExitPrice;

  /// No description provided for @investingProfitBeforeCosts.
  ///
  /// In en, this message translates to:
  /// **'Profit / loss (before fees and funding)'**
  String get investingProfitBeforeCosts;

  /// No description provided for @investingStillOpen.
  ///
  /// In en, this message translates to:
  /// **'Still open'**
  String get investingStillOpen;

  /// No description provided for @investingOrderAccepted.
  ///
  /// In en, this message translates to:
  /// **'Order placed'**
  String get investingOrderAccepted;

  /// No description provided for @investingCloseOrderAccepted.
  ///
  /// In en, this message translates to:
  /// **'Close order placed'**
  String get investingCloseOrderAccepted;

  /// No description provided for @investingOrderPendingFill.
  ///
  /// In en, this message translates to:
  /// **'Your order was accepted. It may fill over time. You can review or cancel it in Investing.'**
  String get investingOrderPendingFill;

  /// No description provided for @investingCurrentPrice.
  ///
  /// In en, this message translates to:
  /// **'Current price'**
  String get investingCurrentPrice;

  /// No description provided for @investingInsufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Not enough balance for this trade.'**
  String get investingInsufficientBalance;

  /// No description provided for @investingTradeRejected.
  ///
  /// In en, this message translates to:
  /// **'The exchange rejected this request. Review your orders before trying again.'**
  String get investingTradeRejected;

  /// No description provided for @investingSubmissionUnknown.
  ///
  /// In en, this message translates to:
  /// **'The exchange has not confirmed the result. Check your orders and balance before trying again.'**
  String get investingSubmissionUnknown;

  /// No description provided for @investingApprovalExpired.
  ///
  /// In en, this message translates to:
  /// **'Approval expired. Review the trade and approve it again.'**
  String get investingApprovalExpired;

  /// No description provided for @investingLeverageCapped.
  ///
  /// In en, this message translates to:
  /// **'Kute limits leverage to {max}x in your region.'**
  String investingLeverageCapped(int max);

  /// No description provided for @investingMarginMode.
  ///
  /// In en, this message translates to:
  /// **'Margin mode'**
  String get investingMarginMode;

  /// No description provided for @investingCrossMargin.
  ///
  /// In en, this message translates to:
  /// **'Shared balance'**
  String get investingCrossMargin;

  /// No description provided for @investingIsolatedMargin.
  ///
  /// In en, this message translates to:
  /// **'Separate balance'**
  String get investingIsolatedMargin;

  /// No description provided for @investingReturnOnInvestment.
  ///
  /// In en, this message translates to:
  /// **'Return on investment'**
  String get investingReturnOnInvestment;

  /// No description provided for @investingCollateral.
  ///
  /// In en, this message translates to:
  /// **'Collateral'**
  String get investingCollateral;

  /// No description provided for @investingFundingPaid.
  ///
  /// In en, this message translates to:
  /// **'Funding paid'**
  String get investingFundingPaid;

  /// No description provided for @investingFundingReceived.
  ///
  /// In en, this message translates to:
  /// **'Funding received'**
  String get investingFundingReceived;

  /// No description provided for @investingDepositsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing deposits are temporarily unavailable'**
  String get investingDepositsUnavailable;

  /// No description provided for @investingWithdrawalsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing withdrawals are temporarily unavailable'**
  String get investingWithdrawalsUnavailable;

  /// No description provided for @betReceiptCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get betReceiptCost;

  /// No description provided for @betReceiptPayout.
  ///
  /// In en, this message translates to:
  /// **'Payout if you win'**
  String get betReceiptPayout;

  /// No description provided for @betReceiptUpdating.
  ///
  /// In en, this message translates to:
  /// **'Final amounts are updating.'**
  String get betReceiptUpdating;

  /// No description provided for @betViewPrediction.
  ///
  /// In en, this message translates to:
  /// **'View prediction'**
  String get betViewPrediction;

  /// No description provided for @betSaleProceeds.
  ///
  /// In en, this message translates to:
  /// **'Proceeds before fees'**
  String get betSaleProceeds;

  /// No description provided for @betSaleReturn.
  ///
  /// In en, this message translates to:
  /// **'Estimated profit / loss before fees'**
  String get betSaleReturn;

  /// No description provided for @betAddFundsToPredict.
  ///
  /// In en, this message translates to:
  /// **'Add funds to predict'**
  String get betAddFundsToPredict;

  /// No description provided for @betMarketNotReady.
  ///
  /// In en, this message translates to:
  /// **'This market is not open yet. Try again in a moment.'**
  String get betMarketNotReady;

  /// No description provided for @betSaleNoBuyers.
  ///
  /// In en, this message translates to:
  /// **'No one is buying this outcome right now. You can wait or keep your shares.'**
  String get betSaleNoBuyers;

  /// No description provided for @betSaleTooThin.
  ///
  /// In en, this message translates to:
  /// **'There are not enough buyers at this price. Try a smaller amount or wait.'**
  String get betSaleTooThin;

  /// No description provided for @betSaleBalanceChanged.
  ///
  /// In en, this message translates to:
  /// **'Your available shares changed. Refresh your position and review again.'**
  String get betSaleBalanceChanged;

  /// No description provided for @betMarketEndedReview.
  ///
  /// In en, this message translates to:
  /// **'This market has ended. Refresh your position to see the available actions.'**
  String get betMarketEndedReview;

  /// No description provided for @betApprovalRefresh.
  ///
  /// In en, this message translates to:
  /// **'Your approval could not be verified. Review the action again.'**
  String get betApprovalRefresh;

  /// No description provided for @betActionNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'This action did not complete. Check your balance and activity before trying again.'**
  String get betActionNotCompleted;

  /// No description provided for @investingPerps.
  ///
  /// In en, this message translates to:
  /// **'Perps'**
  String get investingPerps;

  /// No description provided for @investingCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get investingCrypto;

  /// No description provided for @investingSpot.
  ///
  /// In en, this message translates to:
  /// **'Spot'**
  String get investingSpot;

  /// No description provided for @investingStocks.
  ///
  /// In en, this message translates to:
  /// **'Stocks'**
  String get investingStocks;

  /// No description provided for @investingCommodities.
  ///
  /// In en, this message translates to:
  /// **'Commodities'**
  String get investingCommodities;

  /// No description provided for @investingIndices.
  ///
  /// In en, this message translates to:
  /// **'Indices'**
  String get investingIndices;

  /// No description provided for @investingPrelaunch.
  ///
  /// In en, this message translates to:
  /// **'Pre-launch'**
  String get investingPrelaunch;

  /// No description provided for @investingHip3.
  ///
  /// In en, this message translates to:
  /// **'HIP-3'**
  String get investingHip3;

  /// No description provided for @investingKindOwn.
  ///
  /// In en, this message translates to:
  /// **'Spot'**
  String get investingKindOwn;

  /// No description provided for @investingLowLiquidity.
  ///
  /// In en, this message translates to:
  /// **'Low liquidity'**
  String get investingLowLiquidity;

  /// No description provided for @investingStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get investingStats;

  /// No description provided for @investingAboutMarket.
  ///
  /// In en, this message translates to:
  /// **'About {name}'**
  String investingAboutMarket(String name);

  /// No description provided for @investingKindLeveraged.
  ///
  /// In en, this message translates to:
  /// **'Perp'**
  String get investingKindLeveraged;

  /// No description provided for @investingSlipHoldingCost.
  ///
  /// In en, this message translates to:
  /// **'Holding this costs about {amount} a day at the current rate.'**
  String investingSlipHoldingCost(String amount);

  /// No description provided for @investingSlipHoldingPaid.
  ///
  /// In en, this message translates to:
  /// **'At the current rate this position is paid about {amount} a day, and that can turn into a cost.'**
  String investingSlipHoldingPaid(String amount);

  /// No description provided for @investingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get investingCancelled;

  /// No description provided for @investingAllCancelled.
  ///
  /// In en, this message translates to:
  /// **'Orders cancelled'**
  String get investingAllCancelled;

  /// No description provided for @investingRecurringStopped.
  ///
  /// In en, this message translates to:
  /// **'Order stopped'**
  String get investingRecurringStopped;

  /// No description provided for @investingCancelUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Cancellation is not confirmed. Check your open orders before trying again.'**
  String get investingCancelUnconfirmed;

  /// No description provided for @investingOrderType.
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get investingOrderType;

  /// No description provided for @investingReference.
  ///
  /// In en, this message translates to:
  /// **'Order reference'**
  String get investingReference;

  /// No description provided for @investingCloseRemainderNote.
  ///
  /// In en, this message translates to:
  /// **'Your balance will update in a moment. Check open orders for any remaining close order.'**
  String get investingCloseRemainderNote;

  /// No description provided for @betSalePending.
  ///
  /// In en, this message translates to:
  /// **'Sale status pending'**
  String get betSalePending;

  /// No description provided for @betSalePendingDetail.
  ///
  /// In en, this message translates to:
  /// **'No fill is confirmed yet. Check your positions and open orders before trying again.'**
  String get betSalePendingDetail;

  /// No description provided for @betClaimUpdating.
  ///
  /// In en, this message translates to:
  /// **'Claim confirmed. The credited amount is updating.'**
  String get betClaimUpdating;

  /// No description provided for @betClaimAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your Predictions balance.'**
  String get betClaimAdded;

  /// No description provided for @investingCancellationIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some orders could not be identified. Nothing was cancelled. Refresh your orders and try again.'**
  String get investingCancellationIncomplete;

  /// No description provided for @investingOrderCount.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get investingOrderCount;

  /// No description provided for @investingCancellationDetails.
  ///
  /// In en, this message translates to:
  /// **'Any amounts already filled remain in your account.'**
  String get investingCancellationDetails;

  /// No description provided for @betPreviousOrderChecked.
  ///
  /// In en, this message translates to:
  /// **'Previous order checked. Review your orders and balance before continuing.'**
  String get betPreviousOrderChecked;

  /// No description provided for @walletPortfolioAction.
  ///
  /// In en, this message translates to:
  /// **'Portfolio'**
  String get walletPortfolioAction;

  /// No description provided for @walletActionsWalletChanged.
  ///
  /// In en, this message translates to:
  /// **'The wallet changed. Reopen the actions menu to continue.'**
  String get walletActionsWalletChanged;

  /// No description provided for @ledgerBuilderReviewEach.
  ///
  /// In en, this message translates to:
  /// **'Review each prediction on your Ledger. Setup or an uncertain submission pauses the portfolio.'**
  String get ledgerBuilderReviewEach;

  /// No description provided for @ledgerBuilderCashUnknown.
  ///
  /// In en, this message translates to:
  /// **'Connect your Ledger to verify available funds.'**
  String get ledgerBuilderCashUnknown;

  /// No description provided for @builderRunPaused.
  ///
  /// In en, this message translates to:
  /// **'Portfolio paused. Review the status above before continuing.'**
  String get builderRunPaused;

  /// No description provided for @builderRunReviewRemaining.
  ///
  /// In en, this message translates to:
  /// **'Review remaining predictions'**
  String get builderRunReviewRemaining;

  /// No description provided for @builderRunSummary.
  ///
  /// In en, this message translates to:
  /// **'Portfolio submissions'**
  String get builderRunSummary;

  /// No description provided for @builderOrderStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Order status pending. Check its status before continuing.'**
  String get builderOrderStatusPending;

  /// No description provided for @investingTwapPending.
  ///
  /// In en, this message translates to:
  /// **'Your previous timed order may already be running. New timed orders are blocked until its status is known. Check your Hyperliquid account before continuing.'**
  String get investingTwapPending;

  /// No description provided for @investingTwapPreviouslyAccepted.
  ///
  /// In en, this message translates to:
  /// **'The previous timed order was accepted. No new order was sent. Review your account before placing another.'**
  String get investingTwapPreviouslyAccepted;

  /// No description provided for @investingTwapPreviouslyRejected.
  ///
  /// In en, this message translates to:
  /// **'The previous timed order was not accepted. No new order was sent. Review the order before trying again.'**
  String get investingTwapPreviouslyRejected;

  /// No description provided for @investingTwapPreviouslyExpired.
  ///
  /// In en, this message translates to:
  /// **'The previous timed order\'s window has ended and its result was never confirmed. No new order was sent. Check your Hyperliquid account for fills before placing another.'**
  String get investingTwapPreviouslyExpired;

  /// No description provided for @investingTotal.
  ///
  /// In en, this message translates to:
  /// **'Investing total'**
  String get investingTotal;

  /// No description provided for @predictionsTotal.
  ///
  /// In en, this message translates to:
  /// **'Predictions total'**
  String get predictionsTotal;

  /// No description provided for @investingInOpenOrders.
  ///
  /// In en, this message translates to:
  /// **'{amount} in open orders'**
  String investingInOpenOrders(String amount);

  /// No description provided for @portfolioTabOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get portfolioTabOpen;

  /// No description provided for @portfolioTabOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get portfolioTabOrders;

  /// No description provided for @portfolioTabStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get portfolioTabStatistics;

  /// No description provided for @sendMoreThanAvailable.
  ///
  /// In en, this message translates to:
  /// **'That is more than you have available.'**
  String get sendMoreThanAvailable;

  /// No description provided for @receiveRequestAmount.
  ///
  /// In en, this message translates to:
  /// **'Request amount'**
  String get receiveRequestAmount;

  /// No description provided for @receiveBackToBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Back to Bitcoin'**
  String get receiveBackToBitcoin;

  /// No description provided for @sendRecentRecipients.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sendRecentRecipients;

  /// No description provided for @sendClipboardAddressFound.
  ///
  /// In en, this message translates to:
  /// **'Address found in clipboard. Use it?'**
  String get sendClipboardAddressFound;

  /// No description provided for @useIt.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get useIt;

  /// No description provided for @sendFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment not sent'**
  String get sendFailedTitle;

  /// No description provided for @scannerCameraAccessOff.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Open Settings to allow it.'**
  String get scannerCameraAccessOff;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @sendChooseAccountFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose an available account before sending.'**
  String get sendChooseAccountFirst;

  /// No description provided for @sendWaitForFee.
  ///
  /// In en, this message translates to:
  /// **'Wait for the network fee, then review the payment.'**
  String get sendWaitForFee;

  /// No description provided for @sendFeeEstimateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not estimate the network fee.'**
  String get sendFeeEstimateFailed;

  /// No description provided for @lightningInvoiceMemo.
  ///
  /// In en, this message translates to:
  /// **'Payment to a Kute user'**
  String get lightningInvoiceMemo;

  /// No description provided for @sendEstimatedNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Estimated network fee'**
  String get sendEstimatedNetworkFee;

  /// No description provided for @searchInvestmentsHint.
  ///
  /// In en, this message translates to:
  /// **'Search investments'**
  String get searchInvestmentsHint;

  /// No description provided for @searchPredictionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search predictions'**
  String get searchPredictionsHint;

  /// Name of the dollar balance as an asset row in the cross asset pickers.
  ///
  /// In en, this message translates to:
  /// **'Dollars'**
  String get assetDollars;

  /// Second line on the Dollars row in the move sheet source picker, where the dollar balance funds a venue deposit.
  ///
  /// In en, this message translates to:
  /// **'Pay with your dollar balance'**
  String get moveSourceDollarsSubtitle;

  /// Placeholder for the recipient field when the send destination is a dollar balance.
  ///
  /// In en, this message translates to:
  /// **'Dollar account address'**
  String get sendDollarAccountAddressHint;

  /// Body line while the signing screen is connecting to a Bluetooth signing device.
  ///
  /// In en, this message translates to:
  /// **'Keep {device} nearby and unlocked.'**
  String hwSignKeepDeviceNearby(String device);

  /// Title of the signing stage while the Jade waits for its PIN.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Jade'**
  String get hwSignUnlockJadeTitle;

  /// Body of the signing stage while the Jade waits for its PIN.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN on the device.'**
  String get hwSignUnlockJadeBody;

  /// Title once the hardware device has signed and the payment can be broadcast.
  ///
  /// In en, this message translates to:
  /// **'Ready to send'**
  String get hwSignReadyTitle;

  /// Body once the hardware device has signed and the payment can be broadcast.
  ///
  /// In en, this message translates to:
  /// **'Your device signed it. Nothing leaves your wallet until you send.'**
  String get hwSignReadyBody;

  /// Title while the signed transaction is being broadcast.
  ///
  /// In en, this message translates to:
  /// **'Sending your payment'**
  String get hwSignSendingTitle;

  /// Body while the signed transaction is being broadcast.
  ///
  /// In en, this message translates to:
  /// **'This takes a few seconds. Keep the app open.'**
  String get hwSignSendingBody;

  /// Title of the screen that sends the dollar balance to an outside address.
  ///
  /// In en, this message translates to:
  /// **'Send dollars'**
  String get usdSendTitle;

  /// Hint above the searchable coin list on the dollar send screen.
  ///
  /// In en, this message translates to:
  /// **'Pick what they receive. Your dollars are converted on the way out.'**
  String get usdSendPickCoin;

  /// Placeholder in the recipient address field of the dollar send screen.
  ///
  /// In en, this message translates to:
  /// **'Paste the recipient address'**
  String get usdSendAddressHint;

  /// Inline error when the typed recipient does not belong to the picked network.
  ///
  /// In en, this message translates to:
  /// **'That is not a {network} address.'**
  String usdSendAddressWrongNetwork(String network);

  /// Empty state when the live route catalogue has not landed, so the dollar send has no destinations to offer.
  ///
  /// In en, this message translates to:
  /// **'Destinations are still loading. Try again in a moment.'**
  String get usdSendRoutesUnavailable;

  /// Empty state after the route catalogue has finished loading and the dollar send still has no destinations.
  ///
  /// In en, this message translates to:
  /// **'No destinations available right now. Check your connection and try again.'**
  String get usdSendDestinationsUnavailable;

  /// Inline error when the typed dollar amount is under the route minimum.
  ///
  /// In en, this message translates to:
  /// **'The smallest you can send is {amount}.'**
  String usdSendMinimum(String amount);

  /// Inline error when the typed dollar amount is more than the balance.
  ///
  /// In en, this message translates to:
  /// **'You do not have that many dollars.'**
  String get usdSendNotEnough;

  /// Error shown when a dollar send fails, making clear the balance is untouched.
  ///
  /// In en, this message translates to:
  /// **'Could not send. Your dollars did not move.'**
  String get usdSendFailed;

  /// No description provided for @receiveOneOffTag.
  ///
  /// In en, this message translates to:
  /// **'one payment'**
  String get receiveOneOffTag;

  /// No description provided for @receiveOneOffExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String receiveOneOffExpiresIn(String time);

  /// No description provided for @receiveOneOffNewAddress.
  ///
  /// In en, this message translates to:
  /// **'Get a new address'**
  String get receiveOneOffNewAddress;

  /// No description provided for @receiveOneOffAmountTitle.
  ///
  /// In en, this message translates to:
  /// **'How much are you expecting?'**
  String get receiveOneOffAmountTitle;

  /// No description provided for @usdFlowStepCoin.
  ///
  /// In en, this message translates to:
  /// **'Pick a coin'**
  String get usdFlowStepCoin;

  /// No description provided for @usdSendAmountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How many dollars are you sending?'**
  String get usdSendAmountSubtitle;

  /// No description provided for @usdReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive dollars'**
  String get usdReceiveTitle;

  /// No description provided for @usdReceivePickCoin.
  ///
  /// In en, this message translates to:
  /// **'Pick what is being sent to you. It lands in your dollars.'**
  String get usdReceivePickCoin;

  /// No description provided for @usdReceiveRoutesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Coins are still loading. Try again in a moment.'**
  String get usdReceiveRoutesUnavailable;

  /// Empty state after the route catalogue has finished loading and the dollar receive still has no coins.
  ///
  /// In en, this message translates to:
  /// **'No coins available right now. Check your connection and try again.'**
  String get usdReceiveCoinsUnavailable;

  /// No description provided for @usdReceiveShareStep.
  ///
  /// In en, this message translates to:
  /// **'Share this'**
  String get usdReceiveShareStep;

  /// No description provided for @usdReceiveShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send only {asset} on {network} to this address.'**
  String usdReceiveShareSubtitle(String asset, String network);

  /// No description provided for @usdReceiveCreating.
  ///
  /// In en, this message translates to:
  /// **'Setting up your address.'**
  String get usdReceiveCreating;

  /// No description provided for @usdReceiveArriving.
  ///
  /// In en, this message translates to:
  /// **'Your dollars land as soon as the payment confirms.'**
  String get usdReceiveArriving;

  /// Quiet line under the bitcoin receive address, followed by a few coin marks. It states a property of the address, not a mode to enter.
  ///
  /// In en, this message translates to:
  /// **'Also accepts'**
  String get receiveAlsoAccepts;

  /// Trailing count of the coins that did not fit as marks on the Also accepts line.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String receiveAlsoAcceptsMore(int count);

  /// Shown in place of the coin grid while the route catalogue's first load is still in flight.
  ///
  /// In en, this message translates to:
  /// **'Coins are still loading. Try again in a moment.'**
  String get receiveCoinsLoading;

  /// Heading of the sheet that lists the coins the bitcoin receive address accepts.
  ///
  /// In en, this message translates to:
  /// **'Your address also accepts'**
  String get receiveAlsoAcceptsTitle;

  /// Subtitle of the Also accepts sheet.
  ///
  /// In en, this message translates to:
  /// **'Pick what is being sent to you. It arrives as bitcoin.'**
  String get receiveAlsoAcceptsSubtitle;

  /// Subtitle of the second pane of the Also accepts sheet, once a coin is picked and it lives on more than one network.
  ///
  /// In en, this message translates to:
  /// **'Which network?'**
  String get receivePickNetwork;

  /// No description provided for @betAdvancedSale.
  ///
  /// In en, this message translates to:
  /// **'Advanced sale'**
  String get betAdvancedSale;

  /// No description provided for @betSaleStatusChecked.
  ///
  /// In en, this message translates to:
  /// **'Sale status checked'**
  String get betSaleStatusChecked;

  /// No description provided for @betSaleStatusCheckedDetail.
  ///
  /// In en, this message translates to:
  /// **'Review your positions and open orders to see where the sale landed.'**
  String get betSaleStatusCheckedDetail;

  /// Sell ticket CTA once a prediction sale matched and its trade is being confirmed on chain (a second or two).
  ///
  /// In en, this message translates to:
  /// **'Sold · confirming'**
  String get betSoldConfirming;

  /// Sell ticket notice when the venue accepted a market sell but nothing matched (e.g. killed when a live game's order delay ended).
  ///
  /// In en, this message translates to:
  /// **'No buyers were left at your price, so nothing was sold. Your shares are safe.'**
  String get betSaleNotMatched;

  /// Sell ticket notice when a matched prediction sale's trade failed on chain (rare).
  ///
  /// In en, this message translates to:
  /// **'The sale matched but did not go through on the network. Your shares are still yours.'**
  String get betSaleFailedOnChain;

  /// Confirmation when a limit sell of a prediction filled in part on arrival; the rest stays under Open orders.
  ///
  /// In en, this message translates to:
  /// **'Sold {sold} of {total} shares at {price}. {remaining} shares are still for sale at your price.'**
  String betLimitSellPartial(
      String sold, String total, String price, String remaining);

  /// Quiet line on the Position sold receipt when the sale matched but the chain had not shown it yet within the wait.
  ///
  /// In en, this message translates to:
  /// **'Settling on the network. Your balance updates in a moment.'**
  String get betSaleSettlingNote;

  /// Prediction slip button (and Portfolio card) while the order is on its way to the venue.
  ///
  /// In en, this message translates to:
  /// **'Placing prediction…'**
  String get betPlacingPrediction;

  /// Prediction slip button (and Portfolio card) once the order matched and its trade is being confirmed on chain (a second or two).
  ///
  /// In en, this message translates to:
  /// **'Matched · confirming'**
  String get betMatchedConfirming;

  /// Prediction slip button while the account's one-time setup (wallet deployment, approvals) runs before or during a placement.
  ///
  /// In en, this message translates to:
  /// **'Setting up your Predictions wallet…'**
  String get betSettingUpWallet;

  /// Prediction slip notice when the Predictions account's one-time setup (wallet deployment, approvals) is still running after the slip's wait. Nothing was sent; Retry joins the running setup.
  ///
  /// In en, this message translates to:
  /// **'Your Predictions account is still being set up. This can take a minute. Try again shortly.'**
  String get betSetupSlow;

  /// Prediction slip notice when the Predictions account's one-time setup failed before the order. Nothing was sent; Retry runs it again.
  ///
  /// In en, this message translates to:
  /// **'Your Predictions account could not finish setting up. Your money is safe. Try again.'**
  String get betSetupFailed;

  /// Prediction slip notice when a fresh deposit was still being converted for trading when the order was ready. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Your deposit is still being made ready to use. Try again in a moment.'**
  String get betDepositStillConverting;

  /// Result screen when an earlier prediction on the account is still being placed in the app, so this one was not sent.
  ///
  /// In en, this message translates to:
  /// **'Your last prediction is still being placed. Check its status in a moment.'**
  String get betPreviousStillPlacing;

  /// Prediction slip button while the venue's allowance for the Predictions balance is refreshed during a placement.
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get betApprovingSpend;

  /// Line on the Prediction placed receipt when a market order filled in part (the rest was cancelled, not resting).
  ///
  /// In en, this message translates to:
  /// **'Bought {bought} of {total} shares at {price}. No more sellers were at your price, so the rest was not bought.'**
  String betBuyPartialMarket(String bought, String total, String price);

  /// Confirmation when a limit prediction filled in part on arrival; the rest rests on the book under Open orders.
  ///
  /// In en, this message translates to:
  /// **'Bought {bought} of {total} shares at {price}. The rest is waiting at your price in Open orders.'**
  String betBuyPartialLimit(String bought, String total, String price);

  /// Prediction slip notice when the venue accepted the order but nothing matched (e.g. killed when a live game's order delay ended).
  ///
  /// In en, this message translates to:
  /// **'No sellers were left at your price, so nothing was bought. Your money was not spent.'**
  String get betBuyNotMatched;

  /// Prediction slip notice when a matched order's trade failed on chain (rare).
  ///
  /// In en, this message translates to:
  /// **'The prediction matched but did not go through on the network. Your money was not spent.'**
  String get betBuyFailedOnChain;

  /// The quiet line on the Send to step stating which coins this money can be sent to. Opens the coin picker.
  ///
  /// In en, this message translates to:
  /// **'Also sends to'**
  String get sendAlsoSendsTo;

  /// Label on the Ledger sell ticket's Advanced page for the kind of order the device will sign.
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get ledgerSellOrderType;

  /// Note under the Ledger sell ticket's Advanced page explaining that nothing on it can be changed.
  ///
  /// In en, this message translates to:
  /// **'These terms are fixed. Your Ledger reviews and signs exactly this order.'**
  String get ledgerSellAdvancedFixedNote;

  /// No description provided for @betSharesToSell.
  ///
  /// In en, this message translates to:
  /// **'Shares to sell'**
  String get betSharesToSell;

  /// No description provided for @betPricePerShare.
  ///
  /// In en, this message translates to:
  /// **'Price per share'**
  String get betPricePerShare;

  /// No description provided for @betOrderDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get betOrderDuration;

  /// No description provided for @betUntilCanceled.
  ///
  /// In en, this message translates to:
  /// **'Until canceled'**
  String get betUntilCanceled;

  /// No description provided for @betProceedsToPredictions.
  ///
  /// In en, this message translates to:
  /// **'To Predictions'**
  String get betProceedsToPredictions;

  /// No description provided for @betYourPosition.
  ///
  /// In en, this message translates to:
  /// **'Your position'**
  String get betYourPosition;

  /// No description provided for @betAdvancedSaleSellingAll.
  ///
  /// In en, this message translates to:
  /// **'Selling your whole position'**
  String get betAdvancedSaleSellingAll;

  /// Line under the Earn chart explaining that the dashed tail is an extrapolation of today's rate, not a payment.
  ///
  /// In en, this message translates to:
  /// **'The dashed line is an estimate at today\'s rate, not money received.'**
  String get usdEarnProjectionNote;

  /// Shown on the Earn tab only while the dollar balance is under the programme minimum. {amount} is that minimum, formatted as money.
  ///
  /// In en, this message translates to:
  /// **'Rewards start once you hold {amount}. They are paid daily in bitcoin.'**
  String usdEarnBelowMinimum(String amount);

  /// Headline label on the Earn chart while the scrub sits on a projected day instead of a paid one.
  ///
  /// In en, this message translates to:
  /// **'Projected at today\'s rate'**
  String get usdEarnProjectedLabel;

  /// Hint under the title of the two-entry picker that chooses what a venue withdrawal delivers: bitcoin or dollars.
  ///
  /// In en, this message translates to:
  /// **'Pick what lands in your spending account.'**
  String get moveWithdrawDestinationHint;

  /// Second line on the Dollars row of the withdrawal destination picker.
  ///
  /// In en, this message translates to:
  /// **'Into your dollar balance'**
  String get moveDestDollarsSubtitle;

  /// Note on the confirmation overlay after a transfer that has to convert. Deliberately states no arrival time, because the app is not told one.
  ///
  /// In en, this message translates to:
  /// **'Conversion ongoing'**
  String get moveConversionOngoing;

  /// No description provided for @quotedReceiveAmountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount of {asset} you will send on {network}.'**
  String quotedReceiveAmountSubtitle(String asset, String network);

  /// No description provided for @quotedReceiveRefundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use an address you control on {network}. If a return is needed and supported, it goes here; fees may apply.'**
  String quotedReceiveRefundSubtitle(String network);

  /// No description provided for @quotedReceiveRefundInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid {network} refund address.'**
  String quotedReceiveRefundInvalid(String network);

  /// No description provided for @quotedReceiveExactAmount.
  ///
  /// In en, this message translates to:
  /// **'Send exactly {amount} in one payment before this address expires.'**
  String quotedReceiveExactAmount(String amount);

  /// No description provided for @quotedReceiveExpired.
  ///
  /// In en, this message translates to:
  /// **'This address has expired. Do not send another payment. Check Activity if you already paid.'**
  String get quotedReceiveExpired;

  /// No description provided for @quotedReceiveExpectedOutput.
  ///
  /// In en, this message translates to:
  /// **'Expected to receive {amount}'**
  String quotedReceiveExpectedOutput(String amount);

  /// No description provided for @quotedReceiveWalletChanged.
  ///
  /// In en, this message translates to:
  /// **'Your account changed. Close this screen and start again.'**
  String get quotedReceiveWalletChanged;

  /// No description provided for @receiveOneOffUseAddress.
  ///
  /// In en, this message translates to:
  /// **'Use a one-time address'**
  String get receiveOneOffUseAddress;

  /// No description provided for @stepUpReasonWithdrawWithSourceFee.
  ///
  /// In en, this message translates to:
  /// **'Confirm withdrawal of {amount}, with up to {fee} network fee. Maximum debit: {total}.'**
  String stepUpReasonWithdrawWithSourceFee(
      String amount, String fee, String total);

  /// No description provided for @errorCopyActivationFeeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check the network activation fee. Try again.'**
  String get errorCopyActivationFeeUnavailable;

  /// No description provided for @errorCopyActivationFeeChanged.
  ///
  /// In en, this message translates to:
  /// **'The network activation fee changed. Review this withdrawal again.'**
  String get errorCopyActivationFeeChanged;

  /// No description provided for @errorCopyActivationFeeBalanceRequired.
  ///
  /// In en, this message translates to:
  /// **'Leave 1 USDC available for the network activation fee, then try again.'**
  String get errorCopyActivationFeeBalanceRequired;

  /// No description provided for @salProgressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing your answer…'**
  String get salProgressPreparing;

  /// No description provided for @salProgressReading.
  ///
  /// In en, this message translates to:
  /// **'Reading your question…'**
  String get salProgressReading;

  /// No description provided for @salProgressConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting the details…'**
  String get salProgressConnecting;

  /// No description provided for @salProgressWriting.
  ///
  /// In en, this message translates to:
  /// **'Putting it into words…'**
  String get salProgressWriting;

  /// No description provided for @salProgressChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the details…'**
  String get salProgressChecking;

  /// No description provided for @receiveRequiredMemo.
  ///
  /// In en, this message translates to:
  /// **'Required memo / tag'**
  String get receiveRequiredMemo;

  /// No description provided for @receiveMemoRequiredWarning.
  ///
  /// In en, this message translates to:
  /// **'Include this memo with your deposit. An address alone is not enough.'**
  String get receiveMemoRequiredWarning;

  /// No description provided for @receiveOwnRefundAddress.
  ///
  /// In en, this message translates to:
  /// **'Use your own wallet address that does not require a memo or tag for refunds.'**
  String get receiveOwnRefundAddress;

  /// No description provided for @standingDepositsRefund.
  ///
  /// In en, this message translates to:
  /// **'Request refund'**
  String get standingDepositsRefund;

  /// No description provided for @standingDepositsRefundRequested.
  ///
  /// In en, this message translates to:
  /// **'Refund requested. It has not been sent yet.'**
  String get standingDepositsRefundRequested;

  /// No description provided for @standingDepositsRefundNote.
  ///
  /// In en, this message translates to:
  /// **'Return this deposit to an address you control on the source network. Network fees may apply.'**
  String get standingDepositsRefundNote;

  /// No description provided for @standingDepositsOperatorRefund.
  ///
  /// In en, this message translates to:
  /// **'This deposit needs provider support to return it.'**
  String get standingDepositsOperatorRefund;

  /// No description provided for @standingDepositsUnknownRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund status is being checked. Do not submit another request.'**
  String get standingDepositsUnknownRefund;

  /// No description provided for @activityNeedsReturn.
  ///
  /// In en, this message translates to:
  /// **'Needs return'**
  String get activityNeedsReturn;

  /// No description provided for @activityReturnRequested.
  ///
  /// In en, this message translates to:
  /// **'Return requested'**
  String get activityReturnRequested;

  /// No description provided for @betOrderAcceptedPendingFill.
  ///
  /// In en, this message translates to:
  /// **'Order accepted. Check your positions and open orders for the fill.'**
  String get betOrderAcceptedPendingFill;

  /// No description provided for @betAccountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not verify your Predictions account. Refresh Predictions and try again.'**
  String get betAccountUnavailable;

  /// No description provided for @betConnectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Polymarket. Check your connection and try again.'**
  String get betConnectionUnavailable;

  /// No description provided for @betFeesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not verify the trading fees. Refresh the estimate and try again.'**
  String get betFeesUnavailable;

  /// No description provided for @betMarketUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This market is not ready to accept this order. Refresh the market and try again.'**
  String get betMarketUnavailable;

  /// No description provided for @betOrderFormatRejected.
  ///
  /// In en, this message translates to:
  /// **'Polymarket rejected the order format. No order was placed.'**
  String get betOrderFormatRejected;

  /// No description provided for @betBuyLiquidityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'There are not enough shares available at this price. Try a smaller amount or wait.'**
  String get betBuyLiquidityUnavailable;

  /// No description provided for @betSideMismatchStopped.
  ///
  /// In en, this message translates to:
  /// **'The order did not match the side you picked, so nothing was placed. Check your pick and try again.'**
  String get betSideMismatchStopped;

  /// No description provided for @betBuyFillsUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount} fills now at this price. Nothing was bought. Try that amount or less.'**
  String betBuyFillsUpTo(String amount);

  /// No description provided for @betBuyPriceMoved.
  ///
  /// In en, this message translates to:
  /// **'The price moved to {price}, past your limit of {limit}, so nothing was bought. Try again at the new price.'**
  String betBuyPriceMoved(String price, String limit);

  /// Beside Advanced on a market order: the most it pays per share (the approved maximum price).
  ///
  /// In en, this message translates to:
  /// **'Max · {price}'**
  String betSlipMaxAt(String price);

  /// The retry button after the price moved past the approved maximum: the new maximum it asks to approve.
  ///
  /// In en, this message translates to:
  /// **'Retry at {price}'**
  String betRetryAtPrice(String price);

  /// No description provided for @betSellPriceMoved.
  ///
  /// In en, this message translates to:
  /// **'The price moved to {price}, under your limit of {limit}, so nothing was sold. Try again at the new price.'**
  String betSellPriceMoved(String price, String limit);

  /// No description provided for @walletsInvestingAndPredictions.
  ///
  /// In en, this message translates to:
  /// **'Investing and Predictions'**
  String get walletsInvestingAndPredictions;

  /// No description provided for @walletsEvmKey.
  ///
  /// In en, this message translates to:
  /// **'Investing & Predictions key'**
  String get walletsEvmKey;

  /// No description provided for @walletsInvestingAccount.
  ///
  /// In en, this message translates to:
  /// **'Investing account'**
  String get walletsInvestingAccount;

  /// No description provided for @walletsInvestingAccountNote.
  ///
  /// In en, this message translates to:
  /// **'Your Investing funds on Hyperliquid live at this address. It is the address of your Investing & Predictions key. Safe to share. It does not give access to your funds.'**
  String get walletsInvestingAccountNote;

  /// No description provided for @walletsPredictionsWallet.
  ///
  /// In en, this message translates to:
  /// **'Predictions wallet'**
  String get walletsPredictionsWallet;

  /// No description provided for @walletsPredictionsWalletNote.
  ///
  /// In en, this message translates to:
  /// **'Your Predictions funds live in this smart wallet on Polymarket, controlled by your Investing & Predictions key. Safe to share. It does not give access to your funds.'**
  String get walletsPredictionsWalletNote;

  /// No description provided for @walletsEvmNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up yet'**
  String get walletsEvmNotSetUp;

  /// Caption under the Investing & Predictions key row on Backup and recovery: the wallet's EVM key comes from the recovery phrase in the standard format (the one MetaMask uses).
  ///
  /// In en, this message translates to:
  /// **'Standard format'**
  String get walletsEvmFormatStandard;

  /// Caption under the Investing & Predictions key row on Backup and recovery: the wallet's EVM key comes from the recovery phrase in the legacy format, which other wallets don't reproduce; the private key export still works.
  ///
  /// In en, this message translates to:
  /// **'Legacy format'**
  String get walletsEvmFormatLegacy;

  /// No description provided for @walletsPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get walletsPrivateKey;

  /// No description provided for @walletsPrivateKeyWarning.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this key controls your Investing and Predictions funds. Never share it.'**
  String get walletsPrivateKeyWarning;

  /// No description provided for @walletsShowPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get walletsShowPrivateKey;

  /// No description provided for @walletsPrivateKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied. The clipboard clears in 60 seconds.'**
  String get walletsPrivateKeyCopied;

  /// No description provided for @walletsPrivateKeyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this key. Try again.'**
  String get walletsPrivateKeyUnavailable;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsNotificationsOn;

  /// No description provided for @settingsNotificationsOffTapToTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Off · Tap to turn on'**
  String get settingsNotificationsOffTapToTurnOn;

  /// No description provided for @settingsNotificationsOffOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Off · Turn on in your device\'s Settings'**
  String get settingsNotificationsOffOpenSystemSettings;

  /// No description provided for @settingsNotificationsSystemSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications for Kute in your device\'s Settings app.'**
  String get settingsNotificationsSystemSettingsHint;

  /// No description provided for @buyUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Buy unavailable'**
  String get buyUnavailableTitle;

  /// No description provided for @buyUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'No purchase providers are available at the moment.'**
  String get buyUnavailableBody;

  /// No description provided for @capabilityComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon.'**
  String get capabilityComingSoon;

  /// No description provided for @capabilityRegionRestricted.
  ///
  /// In en, this message translates to:
  /// **'This feature is restricted in the region your internet connection appears to be in. If that isn\'t where you are, check your network or VPN settings and try again.'**
  String get capabilityRegionRestricted;

  /// No description provided for @capabilityUpdateRequired.
  ///
  /// In en, this message translates to:
  /// **'Update Kute to the latest version to use this feature.'**
  String get capabilityUpdateRequired;

  /// No description provided for @capabilityDeviceRestricted.
  ///
  /// In en, this message translates to:
  /// **'This feature is not available on this device.'**
  String get capabilityDeviceRestricted;

  /// No description provided for @capabilityAccountRestricted.
  ///
  /// In en, this message translates to:
  /// **'This feature is not available for your account yet.'**
  String get capabilityAccountRestricted;

  /// No description provided for @capabilityCountryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify your region with Kute. Please try again.'**
  String get capabilityCountryUnknown;

  /// No description provided for @capabilityPolicyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to check availability with Kute. Please try again.'**
  String get capabilityPolicyUnavailable;

  /// No description provided for @capabilityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This feature is currently unavailable in Kute.'**
  String get capabilityUnavailable;

  /// No description provided for @leverageCapExceeded.
  ///
  /// In en, this message translates to:
  /// **'Leverage above {maxLeverage}x is not available in your region.'**
  String leverageCapExceeded(int maxLeverage);

  /// provider is a venue brand name such as Polymarket or Hyperliquid.
  ///
  /// In en, this message translates to:
  /// **'{provider} is restricted in the region your internet connection appears to be in. If that isn\'t where you are, check your network or VPN settings and try again.'**
  String providerRegionRestricted(String provider);

  /// provider is a venue brand name such as Polymarket or Hyperliquid.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify availability with {provider}. Please try again.'**
  String providerAvailabilityUnknown(String provider);

  /// No description provided for @tradingNotAvailableInRegion.
  ///
  /// In en, this message translates to:
  /// **'Trading is not available in your region.'**
  String get tradingNotAvailableInRegion;

  /// No description provided for @gateNotAvailableFromConnection.
  ///
  /// In en, this message translates to:
  /// **'Not available from this connection'**
  String get gateNotAvailableFromConnection;

  /// No description provided for @gatePredictionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Predictions unavailable'**
  String get gatePredictionsUnavailable;

  /// No description provided for @gateInvestingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing unavailable'**
  String get gateInvestingUnavailable;

  /// No description provided for @capabilityRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Not available in your region'**
  String get capabilityRegionTitle;

  /// No description provided for @gateUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get gateUnavailableTitle;

  /// No description provided for @ledgerInvestingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing with Ledger is currently unavailable.'**
  String get ledgerInvestingUnavailable;

  /// No description provided for @ledgerPredictionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Predictions with Ledger is currently unavailable.'**
  String get ledgerPredictionsUnavailable;

  /// No description provided for @salActionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That action is not available.'**
  String get salActionUnavailable;

  /// No description provided for @salPredictionMarketUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This prediction market is unavailable.'**
  String get salPredictionMarketUnavailable;

  /// No description provided for @salMarketUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This market is unavailable.'**
  String get salMarketUnavailable;

  /// No description provided for @salOpenFromOrder.
  ///
  /// In en, this message translates to:
  /// **'Open Ask Sal from the order to use that control.'**
  String get salOpenFromOrder;

  /// No description provided for @salCouldNotOpenMarket.
  ///
  /// In en, this message translates to:
  /// **'Could not open that market. Please try again.'**
  String get salCouldNotOpenMarket;

  /// No description provided for @sendUnsupportedAddressFormat.
  ///
  /// In en, this message translates to:
  /// **'Unsupported or invalid address format'**
  String get sendUnsupportedAddressFormat;

  /// No description provided for @errorCopyDepositTermsChanged.
  ///
  /// In en, this message translates to:
  /// **'Deposit terms changed. Please try again.'**
  String get errorCopyDepositTermsChanged;

  /// No description provided for @errorCopyReusableDepositTermsChanged.
  ///
  /// In en, this message translates to:
  /// **'Reusable deposit terms changed. Use a one-time deposit address.'**
  String get errorCopyReusableDepositTermsChanged;

  /// No description provided for @errorCopyFeesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load fees. Try again.'**
  String get errorCopyFeesUnavailable;

  /// No description provided for @errorCopyWalletNameLength.
  ///
  /// In en, this message translates to:
  /// **'Enter a wallet name of up to 60 characters.'**
  String get errorCopyWalletNameLength;

  /// No description provided for @errorCopyUnsupportedAddressType.
  ///
  /// In en, this message translates to:
  /// **'Choose a supported Bitcoin address type.'**
  String get errorCopyUnsupportedAddressType;

  /// No description provided for @errorCopyInvalidTwelveWords.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 12-word recovery phrase.'**
  String get errorCopyInvalidTwelveWords;

  /// No description provided for @feeUiEstimatedFees.
  ///
  /// In en, this message translates to:
  /// **'Estimated fees'**
  String get feeUiEstimatedFees;

  /// No description provided for @feeUiNetworkActivation.
  ///
  /// In en, this message translates to:
  /// **'Network activation'**
  String get feeUiNetworkActivation;

  /// No description provided for @feeUiNetworkActivationUpTo.
  ///
  /// In en, this message translates to:
  /// **'Network activation (up to)'**
  String get feeUiNetworkActivationUpTo;

  /// No description provided for @feeUiFeeSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Fee settings unavailable'**
  String get feeUiFeeSettingsUnavailable;

  /// No description provided for @fillExecutionPrice.
  ///
  /// In en, this message translates to:
  /// **'Execution price'**
  String get fillExecutionPrice;

  /// No description provided for @fillDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get fillDirection;

  /// No description provided for @fillId.
  ///
  /// In en, this message translates to:
  /// **'Fill ID'**
  String get fillId;

  /// No description provided for @ledgerTotalWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Total withdrawal'**
  String get ledgerTotalWithdrawal;

  /// No description provided for @hlFillLiquidated.
  ///
  /// In en, this message translates to:
  /// **'Position liquidated'**
  String get hlFillLiquidated;

  /// No description provided for @hlFillBoughtAsset.
  ///
  /// In en, this message translates to:
  /// **'Bought asset'**
  String get hlFillBoughtAsset;

  /// No description provided for @hlFillSoldAsset.
  ///
  /// In en, this message translates to:
  /// **'Sold asset'**
  String get hlFillSoldAsset;

  /// No description provided for @hlFillOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened position'**
  String get hlFillOpened;

  /// No description provided for @hlFillClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed position'**
  String get hlFillClosed;

  /// No description provided for @hlFillReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed position'**
  String get hlFillReversed;

  /// No description provided for @hlFillAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to position'**
  String get hlFillAdded;

  /// No description provided for @hlFillReduced.
  ///
  /// In en, this message translates to:
  /// **'Reduced position'**
  String get hlFillReduced;

  /// No description provided for @hlFillTradeFilled.
  ///
  /// In en, this message translates to:
  /// **'Trade filled'**
  String get hlFillTradeFilled;

  /// No description provided for @notificationsNewCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new notification} other{{count} new notifications}}'**
  String notificationsNewCount(int count);

  /// No description provided for @notificationsSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Your notifications'**
  String get notificationsSheetTitle;

  /// No description provided for @notificationsLoadFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications. Retry'**
  String get notificationsLoadFailedRetry;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Settled predictions and closing trades appear here.'**
  String get notificationsEmpty;

  /// No description provided for @hlActivityRefreshFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh trades. Retry'**
  String get hlActivityRefreshFailedRetry;

  /// No description provided for @poweredByProvider.
  ///
  /// In en, this message translates to:
  /// **'Powered by {provider}'**
  String poweredByProvider(String provider);

  /// No description provided for @comingSoonWorkingOn.
  ///
  /// In en, this message translates to:
  /// **'We\'re working hard to bring {title} to Kute. Stay tuned!'**
  String comingSoonWorkingOn(String title);

  /// No description provided for @pendingDepositArriving.
  ///
  /// In en, this message translates to:
  /// **'≈ {amount} arriving · deposit processing'**
  String pendingDepositArriving(String amount);

  /// No description provided for @pendingWithdrawalLeaving.
  ///
  /// In en, this message translates to:
  /// **'≈ {amount} leaving · withdrawal processing'**
  String pendingWithdrawalLeaving(String amount);

  /// No description provided for @btcPredictPriceToBeat.
  ///
  /// In en, this message translates to:
  /// **'Price to beat'**
  String get btcPredictPriceToBeat;

  /// No description provided for @liveBadge.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveBadge;

  /// No description provided for @addWalletCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create New Wallet'**
  String get addWalletCreateNew;

  /// No description provided for @addWalletCreateNewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Instant setup for daily spending.'**
  String get addWalletCreateNewSubtitle;

  /// No description provided for @addWalletRecover.
  ///
  /// In en, this message translates to:
  /// **'Recover Wallet'**
  String get addWalletRecover;

  /// No description provided for @addWalletRecoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore using 12/24 seed words.'**
  String get addWalletRecoverSubtitle;

  /// No description provided for @addWalletSeedSignerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Air-gapped DIY signer'**
  String get addWalletSeedSignerSubtitle;

  /// No description provided for @addWalletKruxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open-source air-gapped signer'**
  String get addWalletKruxSubtitle;

  /// No description provided for @addWalletOther.
  ///
  /// In en, this message translates to:
  /// **'Other Wallet'**
  String get addWalletOther;

  /// No description provided for @addWalletTrackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor any Bitcoin address (view only).'**
  String get addWalletTrackSubtitle;

  /// No description provided for @addWalletImportDevice.
  ///
  /// In en, this message translates to:
  /// **'Import {device}'**
  String addWalletImportDevice(String device);

  /// No description provided for @addWalletImportWallet.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get addWalletImportWallet;

  /// No description provided for @btcSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new wallet or restore one you already have.'**
  String get btcSetupSubtitle;

  /// No description provided for @btcSetupCreateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A separate wallet with a new 12-word recovery phrase.'**
  String get btcSetupCreateSubtitle;

  /// No description provided for @btcSetupRecoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Recover with 12 words'**
  String get btcSetupRecoverTitle;

  /// No description provided for @btcSetupRecoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore your Bitcoin wallet with its recovery phrase.'**
  String get btcSetupRecoverSubtitle;

  /// No description provided for @btcSetupUnlockFirst.
  ///
  /// In en, this message translates to:
  /// **'Unlock Kute before adding a wallet.'**
  String get btcSetupUnlockFirst;

  /// No description provided for @btcSetupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the Bitcoin wallet. Check the name and try again.'**
  String get btcSetupCreateFailed;

  /// No description provided for @btcSetupCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Bitcoin wallet'**
  String get btcSetupCreateTitle;

  /// No description provided for @btcSetupCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Send and receive Bitcoin with a separate 12-word recovery phrase.'**
  String get btcSetupCreateBody;

  /// No description provided for @btcSetupBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your 12 words'**
  String get btcSetupBackupTitle;

  /// No description provided for @btcSetupBackupBody.
  ///
  /// In en, this message translates to:
  /// **'Write them down somewhere safe. You need them to recover this wallet.'**
  String get btcSetupBackupBody;

  /// No description provided for @btcSetupCreateOrRecover.
  ///
  /// In en, this message translates to:
  /// **'Create or recover with 12 words'**
  String get btcSetupCreateOrRecover;

  /// No description provided for @kuteTagline01.
  ///
  /// In en, this message translates to:
  /// **'The old system wasn’t built for you. So we built a new one.'**
  String get kuteTagline01;

  /// No description provided for @kuteTagline02.
  ///
  /// In en, this message translates to:
  /// **'They made money complicated. We made it simple.'**
  String get kuteTagline02;

  /// No description provided for @kuteTagline03.
  ///
  /// In en, this message translates to:
  /// **'You don’t need permission to build wealth.'**
  String get kuteTagline03;

  /// No description provided for @kuteTagline04.
  ///
  /// In en, this message translates to:
  /// **'Your money. Your future. Your terms.'**
  String get kuteTagline04;

  /// No description provided for @kuteTagline05.
  ///
  /// In en, this message translates to:
  /// **'Own a little today. Own your future tomorrow.'**
  String get kuteTagline05;

  /// No description provided for @kuteTagline06.
  ///
  /// In en, this message translates to:
  /// **'Stop renting your future. Start owning it.'**
  String get kuteTagline06;

  /// No description provided for @kuteTagline07.
  ///
  /// In en, this message translates to:
  /// **'The future belongs to the people who build it.'**
  String get kuteTagline07;

  /// No description provided for @kuteTagline08.
  ///
  /// In en, this message translates to:
  /// **'You’re not behind. You’re just getting started.'**
  String get kuteTagline08;

  /// No description provided for @kuteTagline09.
  ///
  /// In en, this message translates to:
  /// **'Big things start small.'**
  String get kuteTagline09;

  /// No description provided for @kuteTagline10.
  ///
  /// In en, this message translates to:
  /// **'The hardest part is starting. You already did.'**
  String get kuteTagline10;

  /// No description provided for @kuteTagline11.
  ///
  /// In en, this message translates to:
  /// **'Brighter days aren’t coming on their own. You’re building them.'**
  String get kuteTagline11;

  /// No description provided for @kuteTagline12.
  ///
  /// In en, this message translates to:
  /// **'The best time to start was yesterday. The second best is now.'**
  String get kuteTagline12;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Change starts with you'**
  String get splashTagline;

  /// No description provided for @shareCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite friends, earn together'**
  String get shareCodeTitle;

  /// No description provided for @shareCodeStartUsing.
  ///
  /// In en, this message translates to:
  /// **'Start using Kute'**
  String get shareCodeStartUsing;

  /// No description provided for @shareCodeSettingUp.
  ///
  /// In en, this message translates to:
  /// **'Setting up your code…'**
  String get shareCodeSettingUp;

  /// No description provided for @shareCodeTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Your code is being created. You can find it any time in Settings → Earn.'**
  String get shareCodeTimedOut;

  /// No description provided for @referrerCaptureInvalid.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify your invite code. Enter it manually if you have one.'**
  String get referrerCaptureInvalid;

  /// No description provided for @referrerCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that code. Double-check with your friend.'**
  String get referrerCodeNotFound;

  /// No description provided for @referrerCodeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the code. Check your connection and try again.'**
  String get referrerCodeNetwork;

  /// No description provided for @referrerPartnerInvite.
  ///
  /// In en, this message translates to:
  /// **'{tier} partner invite'**
  String referrerPartnerInvite(String tier);

  /// No description provided for @referrerGotCode.
  ///
  /// In en, this message translates to:
  /// **'Got a friend\'s code?'**
  String get referrerGotCode;

  /// No description provided for @referrerCodeAdded.
  ///
  /// In en, this message translates to:
  /// **'Code added'**
  String get referrerCodeAdded;

  /// No description provided for @referrerAddLater.
  ///
  /// In en, this message translates to:
  /// **'You can also add it later from Settings → Earn (within 7 days).'**
  String get referrerAddLater;

  /// No description provided for @referrerSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip, I don\'t have a code'**
  String get referrerSkip;

  /// No description provided for @recoverBtcFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not recover the Bitcoin wallet. Check the 12 words and try again.'**
  String get recoverBtcFailed;

  /// No description provided for @recoverOriginalAddressType.
  ///
  /// In en, this message translates to:
  /// **'Original address type'**
  String get recoverOriginalAddressType;

  /// No description provided for @recoverOriginalAddressTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the type used by the wallet you are restoring.'**
  String get recoverOriginalAddressTypeSubtitle;

  /// No description provided for @recoverAddressesStartWith.
  ///
  /// In en, this message translates to:
  /// **'Addresses start with {prefix}'**
  String recoverAddressesStartWith(String prefix);

  /// No description provided for @recoverPasskeyCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String recoverPasskeyCreated(String date);

  /// No description provided for @recoverFoundOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Found on this device. Check the balance looks right before you restore.'**
  String get recoverFoundOnDevice;

  /// Shown on the recover screen while the passkey prompt confirms the chosen wallet.
  ///
  /// In en, this message translates to:
  /// **'Confirm to restore {wallet}.'**
  String recoverConfirmWallet(String wallet);

  /// No description provided for @btcSetupCreateTitleShort.
  ///
  /// In en, this message translates to:
  /// **'Create new wallet'**
  String get btcSetupCreateTitleShort;

  /// No description provided for @btcSetupWalletNameHint.
  ///
  /// In en, this message translates to:
  /// **'Wallet name'**
  String get btcSetupWalletNameHint;

  /// No description provided for @salOrderNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'That order is no longer available to change.'**
  String get salOrderNoLongerAvailable;

  /// No description provided for @salControlUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That control is not available on this screen.'**
  String get salControlUnavailable;

  /// No description provided for @salSwitchToLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to a limit order?'**
  String get salSwitchToLimitTitle;

  /// No description provided for @salOpenLeverageTitle.
  ///
  /// In en, this message translates to:
  /// **'Open leverage settings?'**
  String get salOpenLeverageTitle;

  /// No description provided for @salSwitchToLimitBody.
  ///
  /// In en, this message translates to:
  /// **'This changes the order type. Review the price and amount before placing the order.'**
  String get salSwitchToLimitBody;

  /// No description provided for @salOpenLeverageBody.
  ///
  /// In en, this message translates to:
  /// **'You choose the leverage yourself. This opens the controls without changing the value.'**
  String get salOpenLeverageBody;

  /// No description provided for @salChatWith.
  ///
  /// In en, this message translates to:
  /// **'Chat with Sal'**
  String get salChatWith;

  /// No description provided for @salAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask Sal'**
  String get salAsk;

  /// No description provided for @salUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sal is unavailable right now.'**
  String get salUnavailable;

  /// No description provided for @salDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Factual AI information. Not investment advice.'**
  String get salDisclaimer;

  /// No description provided for @salAskQuestionHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get salAskQuestionHint;

  /// No description provided for @salStopResponse.
  ///
  /// In en, this message translates to:
  /// **'Stop response'**
  String get salStopResponse;

  /// No description provided for @salSendQuestion.
  ///
  /// In en, this message translates to:
  /// **'Send question'**
  String get salSendQuestion;

  /// No description provided for @salPrivateDetailsRemoved.
  ///
  /// In en, this message translates to:
  /// **'Private details removed'**
  String get salPrivateDetailsRemoved;

  /// No description provided for @salPrivateInputBlocked.
  ///
  /// In en, this message translates to:
  /// **'Please remove private details such as wallet addresses, recovery phrases, email addresses or personal account amounts, then ask a general question.'**
  String get salPrivateInputBlocked;

  /// No description provided for @salAlreadyAccepted.
  ///
  /// In en, this message translates to:
  /// **'This question was already accepted. It has not used another question from your daily allowance.'**
  String get salAlreadyAccepted;

  /// No description provided for @salResponseStopped.
  ///
  /// In en, this message translates to:
  /// **'Response stopped.'**
  String get salResponseStopped;

  /// No description provided for @salResponseStoppedEarly.
  ///
  /// In en, this message translates to:
  /// **'Response stopped before completion.'**
  String get salResponseStoppedEarly;

  /// No description provided for @salResetNextDaily.
  ///
  /// In en, this message translates to:
  /// **'at the next daily reset'**
  String get salResetNextDaily;

  /// No description provided for @salResetAt.
  ///
  /// In en, this message translates to:
  /// **'at {time} on {day}/{month}'**
  String salResetAt(String time, String day, String month);

  /// No description provided for @salDailyLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s questions. Your allowance resets {reset}. You can still search markets.'**
  String salDailyLimit(String reset);

  /// No description provided for @salRetryInMinutes.
  ///
  /// In en, this message translates to:
  /// **'in about {minutes} minutes'**
  String salRetryInMinutes(int minutes);

  /// No description provided for @salRetryInAMinute.
  ///
  /// In en, this message translates to:
  /// **'in about a minute'**
  String get salRetryInAMinute;

  /// No description provided for @salRetryInAMoment.
  ///
  /// In en, this message translates to:
  /// **'in a moment'**
  String get salRetryInAMoment;

  /// No description provided for @salRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached your question limit for now. Please ask again {when}.'**
  String salRateLimited(String when);

  /// No description provided for @salCouldNotCompose.
  ///
  /// In en, this message translates to:
  /// **'Sorry, I couldn\'t put that together just now. Mind rephrasing?'**
  String get salCouldNotCompose;

  /// No description provided for @salStubReceiveLightning.
  ///
  /// In en, this message translates to:
  /// **'In Kute, tap Receive and select the spending wallet. You can share its Lightning address or QR. To ask for a specific amount, open “More options”, choose “Request a specific amount”, enter the amount and tap “Create request”. Share the request or QR with the sender. A normal Bitcoin, hardware or watch-only account receives on-chain; select the spending wallet to receive over Lightning.'**
  String get salStubReceiveLightning;

  /// No description provided for @salStubReceiveBitcoin.
  ///
  /// In en, this message translates to:
  /// **'In Kute, tap Receive and select the account that should receive the Bitcoin. Share its Bitcoin address or QR with the sender. The spending wallet also supports Lightning. A normal Bitcoin account receives directly on-chain.'**
  String get salStubReceiveBitcoin;

  /// No description provided for @salStubSendBuy.
  ///
  /// In en, this message translates to:
  /// **'In Kute, tap Receive to get Bitcoin from another wallet. To buy, tap Purchase on Home and follow the Cash App buying flow. To send, tap Send, select the source account, enter the amount, then scan or paste the recipient in “Send to”. Review the destination and fee, then confirm the payment. Normal Bitcoin accounts send on-chain; the spending wallet also supports Lightning. Opening an Investing position on bitcoin does not put Bitcoin into a wallet.'**
  String get salStubSendBuy;

  /// No description provided for @salStubWallets.
  ///
  /// In en, this message translates to:
  /// **'Kute has a spending wallet for Bitcoin and Lightning. In Add wallet, “Bitcoin wallet” creates a separate on-chain account with a new 12-word recovery phrase, or recovers an existing phrase. Its backup appears separately in Seeds. Watch-only accounts monitor Bitcoin without storing signing keys. Keep all recovery words private and enter them only in the wallet recovery screen, never in Sal.'**
  String get salStubWallets;

  /// No description provided for @salStubLimitOrder.
  ///
  /// In en, this message translates to:
  /// **'A limit order sets the highest price you will pay when buying or the lowest price you will accept when selling. It may fill partly or remain unfilled if the market does not reach that price.'**
  String get salStubLimitOrder;

  /// No description provided for @salStubLeverage.
  ///
  /// In en, this message translates to:
  /// **'Leverage creates exposure larger than the margin supporting a position. It magnifies gains and losses. Liquidation can occur when the margin no longer meets the market’s maintenance requirement.'**
  String get salStubLeverage;

  /// No description provided for @salStubFunding.
  ///
  /// In en, this message translates to:
  /// **'Perpetual contracts have no expiry. Funding payments between long and short positions help keep the contract price near its reference price. The rate and who pays can change.'**
  String get salStubFunding;

  /// No description provided for @salStubRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'A recovery phrase can restore access to a wallet. Anyone who has it may be able to control the wallet. Keep it private and never paste it into Sal or a support chat.'**
  String get salStubRecoveryPhrase;

  /// No description provided for @salStubApy.
  ///
  /// In en, this message translates to:
  /// **'APY describes an annualised return that includes compounding. A displayed rate can change and does not guarantee future returns.'**
  String get salStubApy;

  /// No description provided for @salStubPredictionMarket.
  ///
  /// In en, this message translates to:
  /// **'A prediction market trades contracts tied to a stated event. The market’s published resolution rules determine the result. Prices reflect trading activity and are not a guarantee of the outcome.'**
  String get salStubPredictionMarket;

  /// No description provided for @salStubStocksPerps.
  ///
  /// In en, this message translates to:
  /// **'A stock represents ownership in a company. A perpetual contract is a derivative with no expiry and may involve funding and liquidation risk. A stock-linked perpetual does not give ownership of the company’s shares.'**
  String get salStubStocksPerps;

  /// No description provided for @salStubOffline.
  ///
  /// In en, this message translates to:
  /// **'Sal cannot retrieve current public information right now. Please try again shortly. You can still ask a general question about order types, leverage or prediction markets.'**
  String get salStubOffline;

  /// No description provided for @salStubLiveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Live information is unavailable.'**
  String get salStubLiveUnavailable;

  /// No description provided for @searchNoMatchesAskSal.
  ///
  /// In en, this message translates to:
  /// **'No matches for “{query}”. Send it to ask Sal.'**
  String searchNoMatchesAskSal(String query);

  /// No description provided for @searchNoResultsFor.
  ///
  /// In en, this message translates to:
  /// **'No results for “{query}”'**
  String searchNoResultsFor(String query);

  /// No description provided for @searchTypeToSearchMarkets.
  ///
  /// In en, this message translates to:
  /// **'Type to search markets'**
  String get searchTypeToSearchMarkets;

  /// No description provided for @searchOrAskSal.
  ///
  /// In en, this message translates to:
  /// **'Search or ask Sal anything'**
  String get searchOrAskSal;

  /// No description provided for @searchMarketsHint.
  ///
  /// In en, this message translates to:
  /// **'Search markets'**
  String get searchMarketsHint;

  /// No description provided for @searchYourWallet.
  ///
  /// In en, this message translates to:
  /// **'Search your wallet'**
  String get searchYourWallet;

  /// No description provided for @searchNoMatchingActivity.
  ///
  /// In en, this message translates to:
  /// **'No matching activity'**
  String get searchNoMatchingActivity;

  /// No description provided for @searchYourPosition.
  ///
  /// In en, this message translates to:
  /// **'Your position · {outcome}'**
  String searchYourPosition(String outcome);

  /// No description provided for @searchSearchingMarkets.
  ///
  /// In en, this message translates to:
  /// **'Searching markets…'**
  String get searchSearchingMarkets;

  /// No description provided for @searchFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchFilterAll;

  /// No description provided for @searchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searchSearching;

  /// No description provided for @salViewMarket.
  ///
  /// In en, this message translates to:
  /// **'View market'**
  String get salViewMarket;

  /// No description provided for @salPredictionsMarket.
  ///
  /// In en, this message translates to:
  /// **'Predictions market'**
  String get salPredictionsMarket;

  /// No description provided for @salMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get salMarket;

  /// No description provided for @salStockLinkedInvestingMarket.
  ///
  /// In en, this message translates to:
  /// **'Stock-linked Investing market'**
  String get salStockLinkedInvestingMarket;

  /// No description provided for @salCryptoInvestingMarket.
  ///
  /// In en, this message translates to:
  /// **'Crypto Investing market'**
  String get salCryptoInvestingMarket;

  /// No description provided for @salSpotMarket.
  ///
  /// In en, this message translates to:
  /// **'Spot market'**
  String get salSpotMarket;

  /// No description provided for @salStockLinkedSpotMarket.
  ///
  /// In en, this message translates to:
  /// **'Stock-linked spot market'**
  String get salStockLinkedSpotMarket;

  /// No description provided for @salInvestingMarket.
  ///
  /// In en, this message translates to:
  /// **'Investing market'**
  String get salInvestingMarket;

  /// No description provided for @salSemanticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sal. {label}'**
  String salSemanticsLabel(String label);

  /// No description provided for @salSectionPublicActivity.
  ///
  /// In en, this message translates to:
  /// **'Public activity'**
  String get salSectionPublicActivity;

  /// No description provided for @salMarkPrice.
  ///
  /// In en, this message translates to:
  /// **'Mark price'**
  String get salMarkPrice;

  /// No description provided for @salResolutionRules.
  ///
  /// In en, this message translates to:
  /// **'Resolution rules'**
  String get salResolutionRules;

  /// No description provided for @salStockLinkedDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Stock-linked product, not ownership of the underlying shares.'**
  String get salStockLinkedDisclaimer;

  /// No description provided for @salAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String salAsOf(String date);

  /// No description provided for @salShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get salShowLess;

  /// No description provided for @salShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String salShowMore(int count);

  /// No description provided for @salTransactionDate.
  ///
  /// In en, this message translates to:
  /// **'Transaction: {date}'**
  String salTransactionDate(String date);

  /// No description provided for @salDisclosedDate.
  ///
  /// In en, this message translates to:
  /// **'Disclosed: {date}'**
  String salDisclosedDate(String date);

  /// No description provided for @salCouldNotOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Could not open this source.'**
  String get salCouldNotOpenSource;

  /// No description provided for @tnPredictionWon.
  ///
  /// In en, this message translates to:
  /// **'Prediction won'**
  String get tnPredictionWon;

  /// No description provided for @tnPredictionLost.
  ///
  /// In en, this message translates to:
  /// **'Prediction lost'**
  String get tnPredictionLost;

  /// No description provided for @tnPredictionSettled.
  ///
  /// In en, this message translates to:
  /// **'Prediction settled'**
  String get tnPredictionSettled;

  /// No description provided for @tnPredictionBought.
  ///
  /// In en, this message translates to:
  /// **'Prediction bought'**
  String get tnPredictionBought;

  /// No description provided for @tnPredictionSold.
  ///
  /// In en, this message translates to:
  /// **'Prediction sold'**
  String get tnPredictionSold;

  /// No description provided for @tnTradeClosedProfit.
  ///
  /// In en, this message translates to:
  /// **'Trade closed in profit'**
  String get tnTradeClosedProfit;

  /// No description provided for @tnTradeClosed.
  ///
  /// In en, this message translates to:
  /// **'Trade closed'**
  String get tnTradeClosed;

  /// No description provided for @tnClosingFill.
  ///
  /// In en, this message translates to:
  /// **'Closing fill'**
  String get tnClosingFill;

  /// No description provided for @tnSettlementPayout.
  ///
  /// In en, this message translates to:
  /// **'Settlement payout'**
  String get tnSettlementPayout;

  /// No description provided for @tnPositionCostBasis.
  ///
  /// In en, this message translates to:
  /// **'Position cost basis'**
  String get tnPositionCostBasis;

  /// No description provided for @tnReturnLessCost.
  ///
  /// In en, this message translates to:
  /// **'Return less cost basis'**
  String get tnReturnLessCost;

  /// No description provided for @tnProfitDetails.
  ///
  /// In en, this message translates to:
  /// **'Profit details'**
  String get tnProfitDetails;

  /// No description provided for @tnFeesMayAffect.
  ///
  /// In en, this message translates to:
  /// **'Additional fees may affect net profit'**
  String get tnFeesMayAffect;

  /// No description provided for @tnResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get tnResult;

  /// No description provided for @tnCheckClaimStatus.
  ///
  /// In en, this message translates to:
  /// **'Open Positions to check claim status'**
  String get tnCheckClaimStatus;

  /// No description provided for @tnNetProfit.
  ///
  /// In en, this message translates to:
  /// **'Net profit'**
  String get tnNetProfit;

  /// No description provided for @tnTradingPnl.
  ///
  /// In en, this message translates to:
  /// **'Trading P&L'**
  String get tnTradingPnl;

  /// No description provided for @tnAllTradingFees.
  ///
  /// In en, this message translates to:
  /// **'All trading fees'**
  String get tnAllTradingFees;

  /// No description provided for @tnFunding.
  ///
  /// In en, this message translates to:
  /// **'Funding received / paid'**
  String get tnFunding;

  /// No description provided for @tnIncludes.
  ///
  /// In en, this message translates to:
  /// **'Includes'**
  String get tnIncludes;

  /// No description provided for @tnIncludesAllCloses.
  ///
  /// In en, this message translates to:
  /// **'Opening, partial closes and final close'**
  String get tnIncludesAllCloses;

  /// No description provided for @tnClosedPnlExchange.
  ///
  /// In en, this message translates to:
  /// **'Closed P&L (exchange)'**
  String get tnClosedPnlExchange;

  /// No description provided for @tnFillFee.
  ///
  /// In en, this message translates to:
  /// **'Fill fee'**
  String get tnFillFee;

  /// No description provided for @tnFilledSize.
  ///
  /// In en, this message translates to:
  /// **'Filled size'**
  String get tnFilledSize;

  /// No description provided for @tnFillPrice.
  ///
  /// In en, this message translates to:
  /// **'Fill price'**
  String get tnFillPrice;

  /// No description provided for @tnAccounting.
  ///
  /// In en, this message translates to:
  /// **'Accounting'**
  String get tnAccounting;

  /// No description provided for @tnSeeTradeHistory.
  ///
  /// In en, this message translates to:
  /// **'See trade history for all fees and funding'**
  String get tnSeeTradeHistory;

  /// No description provided for @tnClaimCredited.
  ///
  /// In en, this message translates to:
  /// **'Claim credited'**
  String get tnClaimCredited;

  /// No description provided for @tnAverageFillPrice.
  ///
  /// In en, this message translates to:
  /// **'Average fill price'**
  String get tnAverageFillPrice;

  /// No description provided for @tnTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get tnTransaction;

  /// No description provided for @tnFullPosition.
  ///
  /// In en, this message translates to:
  /// **'Full position'**
  String get tnFullPosition;

  /// No description provided for @tnPrediction.
  ///
  /// In en, this message translates to:
  /// **'Prediction'**
  String get tnPrediction;

  /// No description provided for @txValueAtTx.
  ///
  /// In en, this message translates to:
  /// **'Value at tx: {value}  ({change}%)'**
  String txValueAtTx(String value, String change);

  /// No description provided for @txTypeToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get txTypeToken;

  /// No description provided for @txTypeOnChainWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'On-Chain Withdrawal'**
  String get txTypeOnChainWithdrawal;

  /// No description provided for @txTypeOnChain.
  ///
  /// In en, this message translates to:
  /// **'On-Chain'**
  String get txTypeOnChain;

  /// No description provided for @txTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get txTypeUnknown;

  /// No description provided for @openInvestPlacementFailed.
  ///
  /// In en, this message translates to:
  /// **'Placement failed'**
  String get openInvestPlacementFailed;

  /// No description provided for @openInvestUpdatingPosition.
  ///
  /// In en, this message translates to:
  /// **'Updating position…'**
  String get openInvestUpdatingPosition;

  /// No description provided for @openInvestOpenPredictions.
  ///
  /// In en, this message translates to:
  /// **'Open predictions'**
  String get openInvestOpenPredictions;

  /// No description provided for @openInvestPositionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Positions unavailable'**
  String get openInvestPositionsUnavailable;

  /// No description provided for @openInvestNoOpenPredictions.
  ///
  /// In en, this message translates to:
  /// **'No open predictions'**
  String get openInvestNoOpenPredictions;

  /// No description provided for @openInvestNoOpenInvestments.
  ///
  /// In en, this message translates to:
  /// **'No open investments'**
  String get openInvestNoOpenInvestments;

  /// No description provided for @openInvestHeld.
  ///
  /// In en, this message translates to:
  /// **'{amount} held'**
  String openInvestHeld(String amount);

  /// No description provided for @walletNotFound.
  ///
  /// In en, this message translates to:
  /// **'Wallet not found'**
  String get walletNotFound;

  /// No description provided for @settingsSupportInfo.
  ///
  /// In en, this message translates to:
  /// **'Support info'**
  String get settingsSupportInfo;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get settingsAppVersion;

  /// No description provided for @settingsAffiliateId.
  ///
  /// In en, this message translates to:
  /// **'User number'**
  String get settingsAffiliateId;

  /// No description provided for @settingsAffiliateIdNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Not registered yet'**
  String get settingsAffiliateIdNotRegistered;

  /// No description provided for @feeVendorLightningRouting.
  ///
  /// In en, this message translates to:
  /// **'Lightning routing'**
  String get feeVendorLightningRouting;

  /// No description provided for @liveSince.
  ///
  /// In en, this message translates to:
  /// **'since {time}'**
  String liveSince(String time);

  /// No description provided for @jadeBluetoothPermission.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission denied. Please enable it in Settings.'**
  String get jadeBluetoothPermission;

  /// No description provided for @jadeBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is unavailable. Please turn on Bluetooth and try again.'**
  String get jadeBluetoothOff;

  /// No description provided for @jadeScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth scan failed. Please try again.'**
  String get jadeScanFailed;

  /// No description provided for @jadeDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Jade disconnected. Please reconnect and try again.'**
  String get jadeDisconnected;

  /// No description provided for @jadePinAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'PIN authentication failed. Please try again.'**
  String get jadePinAuthFailed;

  /// No description provided for @jadeNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Jade not connected or authenticated'**
  String get jadeNotConnected;

  /// No description provided for @jadeCancelledOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Operation was cancelled on the Jade device.'**
  String get jadeCancelledOnDevice;

  /// No description provided for @jadeBadParams.
  ///
  /// In en, this message translates to:
  /// **'Invalid parameters sent to Jade. Please try again.'**
  String get jadeBadParams;

  /// No description provided for @jadeCommunicationError.
  ///
  /// In en, this message translates to:
  /// **'Communication error with Jade. Please reconnect.'**
  String get jadeCommunicationError;

  /// No description provided for @jadeLocked.
  ///
  /// In en, this message translates to:
  /// **'Jade is not unlocked. Please enter your PIN.'**
  String get jadeLocked;

  /// No description provided for @jadeWrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN entered. Note: 3 failed attempts will reset the device.'**
  String get jadeWrongPin;

  /// No description provided for @jadeNotAJade.
  ///
  /// In en, this message translates to:
  /// **'Device is not a Blockstream Jade. Please check your device.'**
  String get jadeNotAJade;

  /// No description provided for @jadeNotFound.
  ///
  /// In en, this message translates to:
  /// **'No Jade found. Please check:\n1. Jade is powered on\n2. Bluetooth is enabled on Jade and your phone\n\nTip: You can also use QR Mode to scan your xpub.'**
  String get jadeNotFound;

  /// No description provided for @jadePinServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach PIN server. Check your internet or use QR Mode.'**
  String get jadePinServerUnreachable;

  /// No description provided for @jadePinServerEmpty.
  ///
  /// In en, this message translates to:
  /// **'PIN server returned an empty response. Check your internet connection or try QR Mode.'**
  String get jadePinServerEmpty;

  /// No description provided for @jadePinServerBlockstream.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Blockstream PIN server. Check your internet connection or use QR Mode instead.'**
  String get jadePinServerBlockstream;

  /// No description provided for @betConfirmedAppearing.
  ///
  /// In en, this message translates to:
  /// **'Confirmed. Appearing in your predictions…'**
  String get betConfirmedAppearing;

  /// No description provided for @hlDepositArrivedPricesMoved.
  ///
  /// In en, this message translates to:
  /// **'Your deposit arrived. Prices moved since you confirmed. Open the order again to place it.'**
  String get hlDepositArrivedPricesMoved;

  /// No description provided for @hlFundsTimeout.
  ///
  /// In en, this message translates to:
  /// **'Funds didn\'t arrive in time. Try again.'**
  String get hlFundsTimeout;

  /// No description provided for @betAutofireFundsTimeout.
  ///
  /// In en, this message translates to:
  /// **'Your funds are safe in your Polymarket balance, but the prediction couldn\'t be placed automatically. Open Predictions and tap to place it again. It should be instant.'**
  String get betAutofireFundsTimeout;

  /// No description provided for @betAutofireBookUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Polymarket to place the prediction. Your funds are safe in your Polymarket balance. Try again.'**
  String get betAutofireBookUnavailable;

  /// No description provided for @moveInvestingDepositsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Investing deposits are temporarily unavailable.'**
  String get moveInvestingDepositsUnavailable;

  /// No description provided for @movePredictionsWalletNotReady.
  ///
  /// In en, this message translates to:
  /// **'Predictions wallet is not ready yet.'**
  String get movePredictionsWalletNotReady;

  /// No description provided for @moveDepositRouteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This deposit route is temporarily unavailable. Try again later.'**
  String get moveDepositRouteUnavailable;

  /// No description provided for @moveWalletNotReady.
  ///
  /// In en, this message translates to:
  /// **'Wallet not ready yet. Try again in a moment.'**
  String get moveWalletNotReady;

  /// No description provided for @moveSelectCurrency.
  ///
  /// In en, this message translates to:
  /// **'Select currency'**
  String get moveSelectCurrency;

  /// No description provided for @moveLedgerMakeFundsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Open Predictions and choose Make funds available to confirm on your Ledger.'**
  String get moveLedgerMakeFundsAvailable;

  /// No description provided for @moveEstimatedConversionCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated conversion cost'**
  String get moveEstimatedConversionCost;

  /// No description provided for @moveNotQuoted.
  ///
  /// In en, this message translates to:
  /// **'Not quoted'**
  String get moveNotQuoted;

  /// No description provided for @moveCashAppMayCharge.
  ///
  /// In en, this message translates to:
  /// **'Cash App may charge additional fees.'**
  String get moveCashAppMayCharge;

  /// No description provided for @moveAvailableCaption.
  ///
  /// In en, this message translates to:
  /// **'available'**
  String get moveAvailableCaption;

  /// No description provided for @moveFeeAbout.
  ///
  /// In en, this message translates to:
  /// **'Fee about {amount}'**
  String moveFeeAbout(String amount);

  /// No description provided for @moveActionWithAmount.
  ///
  /// In en, this message translates to:
  /// **'{action} {amount}'**
  String moveActionWithAmount(String action, String amount);

  /// No description provided for @moveAmountFrom.
  ///
  /// In en, this message translates to:
  /// **'{amount} from {source}'**
  String moveAmountFrom(String amount, String source);

  /// No description provided for @moveAmountTo.
  ///
  /// In en, this message translates to:
  /// **'{amount} to {destination}'**
  String moveAmountTo(String amount, String destination);

  /// No description provided for @moveBankComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Bank transfers are coming soon.'**
  String get moveBankComingSoon;

  /// No description provided for @moveShownBeforeSigning.
  ///
  /// In en, this message translates to:
  /// **'Shown before signing'**
  String get moveShownBeforeSigning;

  /// No description provided for @movePurchaseFee.
  ///
  /// In en, this message translates to:
  /// **'Purchase fee'**
  String get movePurchaseFee;

  /// No description provided for @moveAddFunds.
  ///
  /// In en, this message translates to:
  /// **'Add funds'**
  String get moveAddFunds;

  /// No description provided for @movePickPayOrDollars.
  ///
  /// In en, this message translates to:
  /// **'Pick how you want to pay, or use your dollar balance.'**
  String get movePickPayOrDollars;

  /// No description provided for @moveHintAWallet.
  ///
  /// In en, this message translates to:
  /// **'a wallet'**
  String get moveHintAWallet;

  /// No description provided for @moveHintTwo.
  ///
  /// In en, this message translates to:
  /// **'{first} or {second}'**
  String moveHintTwo(String first, String second);

  /// No description provided for @moveHintMany.
  ///
  /// In en, this message translates to:
  /// **'{list}, or {last}'**
  String moveHintMany(String list, String last);

  /// No description provided for @moveHintFrom.
  ///
  /// In en, this message translates to:
  /// **'Pick where the money comes from: {list}.'**
  String moveHintFrom(String list);

  /// No description provided for @moveBuyFrom.
  ///
  /// In en, this message translates to:
  /// **'Buy from'**
  String get moveBuyFrom;

  /// No description provided for @moveMoveFrom.
  ///
  /// In en, this message translates to:
  /// **'Move from'**
  String get moveMoveFrom;

  /// No description provided for @moveMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get moveMoveTo;

  /// No description provided for @moveSelectedBadge.
  ///
  /// In en, this message translates to:
  /// **'SELECTED'**
  String get moveSelectedBadge;

  /// No description provided for @durationShortMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String durationShortMinutes(int count);

  /// No description provided for @predictLiveRound.
  ///
  /// In en, this message translates to:
  /// **'Live round'**
  String get predictLiveRound;

  /// No description provided for @predictUpOrDown.
  ///
  /// In en, this message translates to:
  /// **'{asset} Up or Down {minutes}m'**
  String predictUpOrDown(String asset, int minutes);

  /// No description provided for @predictTargetPrice.
  ///
  /// In en, this message translates to:
  /// **'Target {price}'**
  String predictTargetPrice(String price);

  /// No description provided for @predictNoOpenMarketsCategory.
  ///
  /// In en, this message translates to:
  /// **'No open markets in this category right now'**
  String get predictNoOpenMarketsCategory;

  /// No description provided for @predictSharesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shares'**
  String predictSharesCount(String count);

  /// No description provided for @predictStartsIn.
  ///
  /// In en, this message translates to:
  /// **'Starts in {time}'**
  String predictStartsIn(String time);

  /// No description provided for @predictLiveEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Live · Ends in {time}'**
  String predictLiveEndsIn(String time);

  /// No description provided for @predictEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Ends in {time}'**
  String predictEndsIn(String time);

  /// No description provided for @predictYesChance.
  ///
  /// In en, this message translates to:
  /// **'Yes chance'**
  String get predictYesChance;

  /// No description provided for @predictOutcomeLeading.
  ///
  /// In en, this message translates to:
  /// **'{outcome} leading'**
  String predictOutcomeLeading(String outcome);

  /// No description provided for @betSlipBalanceUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating balance…'**
  String get betSlipBalanceUpdating;

  /// No description provided for @betSlipAvailableAmount.
  ///
  /// In en, this message translates to:
  /// **'Available {amount}'**
  String betSlipAvailableAmount(String amount);

  /// No description provided for @betSlipAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced prediction'**
  String get betSlipAdvancedTitle;

  /// No description provided for @betSlipLimitAt.
  ///
  /// In en, this message translates to:
  /// **'Limit · {price}'**
  String betSlipLimitAt(String price);

  /// No description provided for @betSlipLimitExplainer.
  ///
  /// In en, this message translates to:
  /// **'Rests at your price until it fills or you cancel it. It may never fill.'**
  String get betSlipLimitExplainer;

  /// No description provided for @betSlipMarketExplainer.
  ///
  /// In en, this message translates to:
  /// **'Fills right away at the current market price, paying up to {slippage}% more if the price moves before it lands.'**
  String betSlipMarketExplainer(String slippage);

  /// No description provided for @slipExpertSettings.
  ///
  /// In en, this message translates to:
  /// **'Expert settings'**
  String get slipExpertSettings;

  /// No description provided for @betSlipEstimatedShares.
  ///
  /// In en, this message translates to:
  /// **'Estimated shares'**
  String get betSlipEstimatedShares;

  /// No description provided for @betSlipFromPredictions.
  ///
  /// In en, this message translates to:
  /// **'From Predictions'**
  String get betSlipFromPredictions;

  /// No description provided for @marketCardStartsIn.
  ///
  /// In en, this message translates to:
  /// **'Starts in {time}'**
  String marketCardStartsIn(String time);

  /// No description provided for @marketCardStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String marketCardStartsOn(String date);

  /// No description provided for @marketCardSoon.
  ///
  /// In en, this message translates to:
  /// **'soon'**
  String get marketCardSoon;

  /// No description provided for @marketCardEsportsLive.
  ///
  /// In en, this message translates to:
  /// **'Esports live'**
  String get marketCardEsportsLive;

  /// No description provided for @marketCardLiveStream.
  ///
  /// In en, this message translates to:
  /// **'Live stream'**
  String get marketCardLiveStream;

  /// No description provided for @pmOrdersConnectLedger.
  ///
  /// In en, this message translates to:
  /// **'Connect Predictions trading for this Ledger to load orders.'**
  String get pmOrdersConnectLedger;

  /// No description provided for @pmOrdersCancelAllFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel all orders. Try again.'**
  String get pmOrdersCancelAllFailed;

  /// No description provided for @ordersCancelAll.
  ///
  /// In en, this message translates to:
  /// **'Cancel all'**
  String get ordersCancelAll;

  /// No description provided for @betHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Prediction history'**
  String get betHistoryTitle;

  /// No description provided for @betHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No predictions yet'**
  String get betHistoryEmpty;

  /// No description provided for @betHistoryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Your placed, won and lost predictions will show here.'**
  String get betHistoryEmptyBody;

  /// No description provided for @groupNoMatchesIn.
  ///
  /// In en, this message translates to:
  /// **'No matches in {title}'**
  String groupNoMatchesIn(String title);

  /// No description provided for @groupSearchIn.
  ///
  /// In en, this message translates to:
  /// **'Search {title}'**
  String groupSearchIn(String title);

  /// No description provided for @clearRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Market rules'**
  String get clearRulesTitle;

  /// No description provided for @clearRulesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The full resolution rules could not be loaded right now. You can still clear this position.'**
  String get clearRulesUnavailable;

  /// No description provided for @marketResolved.
  ///
  /// In en, this message translates to:
  /// **'Market resolved'**
  String get marketResolved;

  /// No description provided for @slipDependsOnPosition.
  ///
  /// In en, this message translates to:
  /// **'Depends on your open position'**
  String get slipDependsOnPosition;

  /// No description provided for @slipEnterLimitPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a limit price.'**
  String get slipEnterLimitPrice;

  /// No description provided for @slipEnterStartEndPrices.
  ///
  /// In en, this message translates to:
  /// **'Enter start and end prices.'**
  String get slipEnterStartEndPrices;

  /// No description provided for @slipScaleMinOrders.
  ///
  /// In en, this message translates to:
  /// **'Scale needs at least 2 orders.'**
  String get slipScaleMinOrders;

  /// No description provided for @slipTwapDurationRange.
  ///
  /// In en, this message translates to:
  /// **'Duration must be between 5 minutes and 7 days.'**
  String get slipTwapDurationRange;

  /// No description provided for @slipEnterTriggerPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a trigger price.'**
  String get slipEnterTriggerPrice;

  /// No description provided for @slipTpAboveEntry.
  ///
  /// In en, this message translates to:
  /// **'Take-profit must be above entry.'**
  String get slipTpAboveEntry;

  /// No description provided for @slipTpBelowEntry.
  ///
  /// In en, this message translates to:
  /// **'Take-profit must be below entry.'**
  String get slipTpBelowEntry;

  /// No description provided for @slipSlBelowEntry.
  ///
  /// In en, this message translates to:
  /// **'Stop-loss must be below entry.'**
  String get slipSlBelowEntry;

  /// No description provided for @slipSlAboveEntry.
  ///
  /// In en, this message translates to:
  /// **'Stop-loss must be above entry.'**
  String get slipSlAboveEntry;

  /// No description provided for @slipTrailingBelow100.
  ///
  /// In en, this message translates to:
  /// **'Enter a trailing distance below 100%.'**
  String get slipTrailingBelow100;

  /// No description provided for @slipEnterTrailingDistance.
  ///
  /// In en, this message translates to:
  /// **'Enter a trailing distance.'**
  String get slipEnterTrailingDistance;

  /// No description provided for @slipEnterActivationPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter an activation price.'**
  String get slipEnterActivationPrice;

  /// No description provided for @slipYouHold.
  ///
  /// In en, this message translates to:
  /// **'You hold {size} {coin} ({value}).'**
  String slipYouHold(String size, String coin, String value);

  /// No description provided for @slipYouHoldNone.
  ///
  /// In en, this message translates to:
  /// **'You don\'t hold any {coin} to sell.'**
  String slipYouHoldNone(String coin);

  /// No description provided for @slipWaitingForPrice.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a price…'**
  String get slipWaitingForPrice;

  /// No description provided for @slipAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'{side} {coin} · Advanced'**
  String slipAdvancedTitle(String side, String coin);

  /// No description provided for @slipMarketOrder.
  ///
  /// In en, this message translates to:
  /// **'Market order'**
  String get slipMarketOrder;

  /// No description provided for @slipLimitOrder.
  ///
  /// In en, this message translates to:
  /// **'Limit order'**
  String get slipLimitOrder;

  /// No description provided for @slipReduceOnly.
  ///
  /// In en, this message translates to:
  /// **'Reduce only'**
  String get slipReduceOnly;

  /// No description provided for @slipTakeProfitStopLoss.
  ///
  /// In en, this message translates to:
  /// **'Take profit / stop loss'**
  String get slipTakeProfitStopLoss;

  /// No description provided for @slipPostOnly.
  ///
  /// In en, this message translates to:
  /// **'Post only'**
  String get slipPostOnly;

  /// No description provided for @slipMaxSlippageSummary.
  ///
  /// In en, this message translates to:
  /// **'{percent}% max slippage'**
  String slipMaxSlippageSummary(String percent);

  /// No description provided for @slipScaleOrder.
  ///
  /// In en, this message translates to:
  /// **'Scale order'**
  String get slipScaleOrder;

  /// No description provided for @slipStopLimit.
  ///
  /// In en, this message translates to:
  /// **'Stop limit'**
  String get slipStopLimit;

  /// No description provided for @slipStopMarket.
  ///
  /// In en, this message translates to:
  /// **'Stop market'**
  String get slipStopMarket;

  /// No description provided for @slipTakeLimit.
  ///
  /// In en, this message translates to:
  /// **'Take limit'**
  String get slipTakeLimit;

  /// No description provided for @slipTakeMarket.
  ///
  /// In en, this message translates to:
  /// **'Take market'**
  String get slipTakeMarket;

  /// No description provided for @slipTwapOrder.
  ///
  /// In en, this message translates to:
  /// **'TWAP order'**
  String get slipTwapOrder;

  /// No description provided for @slipScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get slipScale;

  /// No description provided for @slipProtectPosition.
  ///
  /// In en, this message translates to:
  /// **'Protect this position'**
  String get slipProtectPosition;

  /// No description provided for @slipAttachTrailing.
  ///
  /// In en, this message translates to:
  /// **'Attach trailing stop'**
  String get slipAttachTrailing;

  /// No description provided for @slipTrailingExplainLong.
  ///
  /// In en, this message translates to:
  /// **'Follows the high and sells the position when the price falls by your distance. Placed as soon as the order fills.'**
  String get slipTrailingExplainLong;

  /// No description provided for @slipTrailingExplainShort.
  ///
  /// In en, this message translates to:
  /// **'Follows the low and buys the position back when the price rises by your distance. Placed as soon as the order fills.'**
  String get slipTrailingExplainShort;

  /// No description provided for @slipPercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get slipPercent;

  /// No description provided for @slipDistancePercent.
  ///
  /// In en, this message translates to:
  /// **'Distance (%)'**
  String get slipDistancePercent;

  /// No description provided for @slipDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get slipDistance;

  /// No description provided for @slipActivationPrice.
  ///
  /// In en, this message translates to:
  /// **'Activation price'**
  String get slipActivationPrice;

  /// No description provided for @slipStartFollowingAtPrice.
  ///
  /// In en, this message translates to:
  /// **'Start following at a price'**
  String get slipStartFollowingAtPrice;

  /// No description provided for @slipTrailingNotPlaced.
  ///
  /// In en, this message translates to:
  /// **'The order filled, but the trailing stop was not placed: {reason}'**
  String slipTrailingNotPlaced(String reason);

  /// No description provided for @slipCross.
  ///
  /// In en, this message translates to:
  /// **'Cross'**
  String get slipCross;

  /// No description provided for @slipIsolated.
  ///
  /// In en, this message translates to:
  /// **'Isolated'**
  String get slipIsolated;

  /// No description provided for @slipMaxLeverage.
  ///
  /// In en, this message translates to:
  /// **'Max {leverage}x'**
  String slipMaxLeverage(String leverage);

  /// No description provided for @slipIsolatedOnly.
  ///
  /// In en, this message translates to:
  /// **'Isolated margin only. This market doesn\'t support cross margin.'**
  String get slipIsolatedOnly;

  /// No description provided for @slipHeld.
  ///
  /// In en, this message translates to:
  /// **'Held: {amount}'**
  String slipHeld(String amount);

  /// No description provided for @slipTotalMargin.
  ///
  /// In en, this message translates to:
  /// **'Total margin'**
  String get slipTotalMargin;

  /// No description provided for @slipStartPrice.
  ///
  /// In en, this message translates to:
  /// **'Start price'**
  String get slipStartPrice;

  /// No description provided for @slipEndPrice.
  ///
  /// In en, this message translates to:
  /// **'End price'**
  String get slipEndPrice;

  /// No description provided for @slipNumberOfOrders.
  ///
  /// In en, this message translates to:
  /// **'Number of orders'**
  String get slipNumberOfOrders;

  /// No description provided for @slipTwapMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes, min 5)'**
  String get slipTwapMinutes;

  /// No description provided for @slipRandomizeTiming.
  ///
  /// In en, this message translates to:
  /// **'Randomize sub-order timing'**
  String get slipRandomizeTiming;

  /// No description provided for @slipTriggerPrice.
  ///
  /// In en, this message translates to:
  /// **'Trigger price'**
  String get slipTriggerPrice;

  /// No description provided for @slipPostOnlyOption.
  ///
  /// In en, this message translates to:
  /// **'Post-only (maker, ALO)'**
  String get slipPostOnlyOption;

  /// No description provided for @slipReduceOnlyOption.
  ///
  /// In en, this message translates to:
  /// **'Reduce-only (never opens a new position)'**
  String get slipReduceOnlyOption;

  /// No description provided for @slipTimeInForce.
  ///
  /// In en, this message translates to:
  /// **'Time in force'**
  String get slipTimeInForce;

  /// No description provided for @slipAttachTpSl.
  ///
  /// In en, this message translates to:
  /// **'Attach take-profit / stop-loss'**
  String get slipAttachTpSl;

  /// No description provided for @slipTakeProfitPrice.
  ///
  /// In en, this message translates to:
  /// **'Take-profit price'**
  String get slipTakeProfitPrice;

  /// No description provided for @slipStopLossPrice.
  ///
  /// In en, this message translates to:
  /// **'Stop-loss price'**
  String get slipStopLossPrice;

  /// No description provided for @slipVerbBuys.
  ///
  /// In en, this message translates to:
  /// **'buys'**
  String get slipVerbBuys;

  /// No description provided for @slipVerbSells.
  ///
  /// In en, this message translates to:
  /// **'sells'**
  String get slipVerbSells;

  /// No description provided for @slipVerbGoesLong.
  ///
  /// In en, this message translates to:
  /// **'goes long'**
  String get slipVerbGoesLong;

  /// No description provided for @slipVerbGoesShort.
  ///
  /// In en, this message translates to:
  /// **'goes short'**
  String get slipVerbGoesShort;

  /// No description provided for @slipMarginCross.
  ///
  /// In en, this message translates to:
  /// **'cross'**
  String get slipMarginCross;

  /// No description provided for @slipMarginIsolated.
  ///
  /// In en, this message translates to:
  /// **'isolated'**
  String get slipMarginIsolated;

  /// No description provided for @slipLeverageSuffix.
  ///
  /// In en, this message translates to:
  /// **' at {leverage}x {mode} margin'**
  String slipLeverageSuffix(String leverage, String mode);

  /// No description provided for @slipReduceSentence.
  ///
  /// In en, this message translates to:
  /// **' It can only reduce your position, never open one.'**
  String get slipReduceSentence;

  /// No description provided for @slipTpSlSentence.
  ///
  /// In en, this message translates to:
  /// **' A take-profit and stop-loss are attached and close the position when hit.'**
  String get slipTpSlSentence;

  /// No description provided for @slipAction.
  ///
  /// In en, this message translates to:
  /// **'{verb} {coin}{leverage}'**
  String slipAction(String verb, String coin, String leverage);

  /// No description provided for @slipSliceAction.
  ///
  /// In en, this message translates to:
  /// **'{verb} a slice of {coin}{leverage}'**
  String slipSliceAction(String verb, String coin, String leverage);

  /// No description provided for @slipExplainMarket.
  ///
  /// In en, this message translates to:
  /// **'Executes now at the best available price, up to {slippage}% from the current price; it {action}.{extra}'**
  String slipExplainMarket(String slippage, String action, String extra);

  /// No description provided for @slipTifIoc.
  ///
  /// In en, this message translates to:
  /// **' Anything not filled immediately is cancelled.'**
  String get slipTifIoc;

  /// No description provided for @slipTifAlo.
  ///
  /// In en, this message translates to:
  /// **' It only ever rests on the book (post-only), so it pays the maker fee.'**
  String get slipTifAlo;

  /// No description provided for @slipTifGtc.
  ///
  /// In en, this message translates to:
  /// **' It rests on the book until filled or cancelled.'**
  String get slipTifGtc;

  /// No description provided for @slipExplainLimit.
  ///
  /// In en, this message translates to:
  /// **'Rests at {price} and fills only at that price or better; it {action}.{extra}'**
  String slipExplainLimit(String price, String action, String extra);

  /// No description provided for @slipExplainScale.
  ///
  /// In en, this message translates to:
  /// **'Places {count} limit orders spread between {start} and {end}; each {action}.{extra}'**
  String slipExplainScale(
      int count, String start, String end, String action, String extra);

  /// No description provided for @slipExplainTwap.
  ///
  /// In en, this message translates to:
  /// **'Splits the order into small market orders over {minutes} minutes to track the average price; it {action}.{extra}'**
  String slipExplainTwap(int minutes, String action, String extra);

  /// No description provided for @slipExplainStopMarket.
  ///
  /// In en, this message translates to:
  /// **'Waits until {coin} trades at {trigger}, then sends a market order that {action}.{extra}'**
  String slipExplainStopMarket(
      String coin, String trigger, String action, String extra);

  /// No description provided for @slipExplainStopLimit.
  ///
  /// In en, this message translates to:
  /// **'Waits until {coin} trades at {trigger}, then places a limit order at {limit} that {action}.{extra}'**
  String slipExplainStopLimit(
      String coin, String trigger, String limit, String action, String extra);

  /// No description provided for @slipExplainTakeMarket.
  ///
  /// In en, this message translates to:
  /// **'Takes profit: once {coin} reaches {trigger}, a market order {action}.{extra}'**
  String slipExplainTakeMarket(
      String coin, String trigger, String action, String extra);

  /// No description provided for @slipExplainTakeLimit.
  ///
  /// In en, this message translates to:
  /// **'Takes profit: once {coin} reaches {trigger}, a limit order at {limit} {action}.{extra}'**
  String slipExplainTakeLimit(
      String coin, String trigger, String limit, String action, String extra);

  /// No description provided for @slipPositionValue.
  ///
  /// In en, this message translates to:
  /// **'Position value'**
  String get slipPositionValue;

  /// No description provided for @slipEstLiquidation.
  ///
  /// In en, this message translates to:
  /// **'Est. liquidation'**
  String get slipEstLiquidation;

  /// No description provided for @slipNotional.
  ///
  /// In en, this message translates to:
  /// **'Notional'**
  String get slipNotional;

  /// No description provided for @slipEstEntry.
  ///
  /// In en, this message translates to:
  /// **'Est. entry'**
  String get slipEstEntry;

  /// No description provided for @slipRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get slipRange;

  /// No description provided for @slipLegsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} legs'**
  String slipLegsCount(int count);

  /// No description provided for @slipOver.
  ///
  /// In en, this message translates to:
  /// **'Over'**
  String get slipOver;

  /// No description provided for @slipMinutesValue.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String slipMinutesValue(int minutes);

  /// No description provided for @slipTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get slipTrigger;

  /// No description provided for @slipLiqNoteCross.
  ///
  /// In en, this message translates to:
  /// **'Estimated from your account equity, your leverage and Hyperliquid\'s maintenance margin (half the initial margin at max leverage). Other positions, fees and funding move it; the venue sets the final figure after execution.'**
  String get slipLiqNoteCross;

  /// No description provided for @slipLiqNoteIsolated.
  ///
  /// In en, this message translates to:
  /// **'Estimated from your margin, your leverage and Hyperliquid\'s maintenance margin (half the initial margin at max leverage). Fees, funding and large-position tiers move it; the venue sets the final figure after execution.'**
  String get slipLiqNoteIsolated;

  /// No description provided for @slipWideSpread.
  ///
  /// In en, this message translates to:
  /// **'Wide spread: {percent}%. Market orders here can fill noticeably away from the mid price.'**
  String slipWideSpread(String percent);

  /// No description provided for @slipCtaSpotNow.
  ///
  /// In en, this message translates to:
  /// **'{side} {coin} now · {amount}'**
  String slipCtaSpotNow(String side, String coin, String amount);

  /// No description provided for @slipCtaGo.
  ///
  /// In en, this message translates to:
  /// **'Go {side} {coin} {leverage}x · {amount}'**
  String slipCtaGo(String side, String coin, String leverage, String amount);

  /// No description provided for @slipCtaLimit.
  ///
  /// In en, this message translates to:
  /// **'Place {side} {coin} limit'**
  String slipCtaLimit(String side, String coin);

  /// No description provided for @slipCtaScale.
  ///
  /// In en, this message translates to:
  /// **'Place {count} scaled {side} orders'**
  String slipCtaScale(int count, String side);

  /// No description provided for @slipCtaTwap.
  ///
  /// In en, this message translates to:
  /// **'Start TWAP · {minutes}m'**
  String slipCtaTwap(int minutes);

  /// No description provided for @slipCtaStop.
  ///
  /// In en, this message translates to:
  /// **'Place stop order'**
  String get slipCtaStop;

  /// No description provided for @slipCtaTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'Place take-profit'**
  String get slipCtaTakeProfit;

  /// No description provided for @closeMarketUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Market unavailable. Try again later.'**
  String get closeMarketUnavailable;

  /// No description provided for @closeOrderDetailsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Order details unavailable for this market.'**
  String get closeOrderDetailsUnavailable;

  /// No description provided for @closeTitle.
  ///
  /// In en, this message translates to:
  /// **'Close {coin}'**
  String closeTitle(String coin);

  /// No description provided for @closeNowPercent.
  ///
  /// In en, this message translates to:
  /// **'Close {percent}% now'**
  String closeNowPercent(int percent);

  /// No description provided for @closeMarketCta.
  ///
  /// In en, this message translates to:
  /// **'Place market close'**
  String get closeMarketCta;

  /// No description provided for @closeLimitCta.
  ///
  /// In en, this message translates to:
  /// **'Place limit close'**
  String get closeLimitCta;

  /// No description provided for @closeStopMarketCta.
  ///
  /// In en, this message translates to:
  /// **'Place stop market close'**
  String get closeStopMarketCta;

  /// No description provided for @closeStopLimitCta.
  ///
  /// In en, this message translates to:
  /// **'Place stop limit close'**
  String get closeStopLimitCta;

  /// No description provided for @closeTakeMarketCta.
  ///
  /// In en, this message translates to:
  /// **'Place take market close'**
  String get closeTakeMarketCta;

  /// No description provided for @closeTakeLimitCta.
  ///
  /// In en, this message translates to:
  /// **'Place take limit close'**
  String get closeTakeLimitCta;

  /// No description provided for @closeTwapCta.
  ///
  /// In en, this message translates to:
  /// **'Place twap close'**
  String get closeTwapCta;

  /// No description provided for @closeTwapMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes, 5–10080)'**
  String get closeTwapMinutes;

  /// No description provided for @trailingClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get trailingClose;

  /// No description provided for @trailingFollowsLowBuys.
  ///
  /// In en, this message translates to:
  /// **'Follows the low, then buys when the price rises by your trailing distance.'**
  String get trailingFollowsLowBuys;

  /// No description provided for @trailingFollowsHighSells.
  ///
  /// In en, this message translates to:
  /// **'Follows the high, then sells when the price falls by your trailing distance.'**
  String get trailingFollowsHighSells;

  /// No description provided for @trailingDistance.
  ///
  /// In en, this message translates to:
  /// **'Trailing distance'**
  String get trailingDistance;

  /// No description provided for @trailingDistanceUsd.
  ///
  /// In en, this message translates to:
  /// **'Distance (USD)'**
  String get trailingDistanceUsd;

  /// No description provided for @trailingActivationPriceUsd.
  ///
  /// In en, this message translates to:
  /// **'Activation price (USD)'**
  String get trailingActivationPriceUsd;

  /// No description provided for @trailingPlace.
  ///
  /// In en, this message translates to:
  /// **'Place trailing stop'**
  String get trailingPlace;

  /// No description provided for @hlOrdersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No resting orders.\nOrders that don\'t fill immediately show up here.'**
  String get hlOrdersEmpty;

  /// No description provided for @hlOrdersStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get hlOrdersStop;

  /// No description provided for @hlOrdersReduceOnly.
  ///
  /// In en, this message translates to:
  /// **'Reduce-only'**
  String get hlOrdersReduceOnly;

  /// No description provided for @hlOrdersTrailingStopMarket.
  ///
  /// In en, this message translates to:
  /// **'Trailing stop market'**
  String get hlOrdersTrailingStopMarket;

  /// No description provided for @hlNoHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get hlNoHistoryYet;

  /// No description provided for @hlClosePosition.
  ///
  /// In en, this message translates to:
  /// **'Close position'**
  String get hlClosePosition;

  /// No description provided for @hlLongsPayShorts.
  ///
  /// In en, this message translates to:
  /// **'Longs pay shorts'**
  String get hlLongsPayShorts;

  /// No description provided for @hlShortsPayLongs.
  ///
  /// In en, this message translates to:
  /// **'Shorts pay longs'**
  String get hlShortsPayLongs;

  /// No description provided for @hlChartEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get hlChartEntry;

  /// No description provided for @hlChartLiq.
  ///
  /// In en, this message translates to:
  /// **'Liq'**
  String get hlChartLiq;

  /// No description provided for @hlChartTrail.
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get hlChartTrail;

  /// No description provided for @hlChartStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get hlChartStop;

  /// No description provided for @hlTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take profit'**
  String get hlTakeProfit;

  /// No description provided for @hlStopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop loss'**
  String get hlStopLoss;

  /// No description provided for @hlBuyLimit.
  ///
  /// In en, this message translates to:
  /// **'Buy limit'**
  String get hlBuyLimit;

  /// No description provided for @hlSellLimit.
  ///
  /// In en, this message translates to:
  /// **'Sell limit'**
  String get hlSellLimit;

  /// No description provided for @hlOrderBookUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Order book unavailable'**
  String get hlOrderBookUnavailable;

  /// No description provided for @hlOrderBook.
  ///
  /// In en, this message translates to:
  /// **'Order book'**
  String get hlOrderBook;

  /// No description provided for @hlEmptyBook.
  ///
  /// In en, this message translates to:
  /// **'Empty book'**
  String get hlEmptyBook;

  /// No description provided for @hlSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread'**
  String get hlSpread;

  /// No description provided for @hlRecentTrades.
  ///
  /// In en, this message translates to:
  /// **'Recent trades'**
  String get hlRecentTrades;

  /// No description provided for @hlWaitingNextTrade.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the next trade'**
  String get hlWaitingNextTrade;

  /// No description provided for @hlMark.
  ///
  /// In en, this message translates to:
  /// **'Mark'**
  String get hlMark;

  /// No description provided for @hlOpenInterest.
  ///
  /// In en, this message translates to:
  /// **'Open interest'**
  String get hlOpenInterest;

  /// No description provided for @hlFunding.
  ///
  /// In en, this message translates to:
  /// **'Funding'**
  String get hlFunding;

  /// No description provided for @hlChartBoughtSize.
  ///
  /// In en, this message translates to:
  /// **'Bought {size}'**
  String hlChartBoughtSize(String size);

  /// No description provided for @hlChartSoldSize.
  ///
  /// In en, this message translates to:
  /// **'Sold {size}'**
  String hlChartSoldSize(String size);

  /// No description provided for @hlChartYouTraded.
  ///
  /// In en, this message translates to:
  /// **'You traded here'**
  String get hlChartYouTraded;

  /// No description provided for @hlChartYouBought.
  ///
  /// In en, this message translates to:
  /// **'You bought here'**
  String get hlChartYouBought;

  /// No description provided for @hlChartYouSold.
  ///
  /// In en, this message translates to:
  /// **'You sold here'**
  String get hlChartYouSold;

  /// No description provided for @hlWithdrawalsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals are temporarily unavailable. Try again later.'**
  String get hlWithdrawalsUnavailable;

  /// No description provided for @hlNoMarketsNow.
  ///
  /// In en, this message translates to:
  /// **'No markets to show right now'**
  String get hlNoMarketsNow;

  /// No description provided for @hlChartFillTitle.
  ///
  /// In en, this message translates to:
  /// **'{action}{coin} at {price}'**
  String hlChartFillTitle(String action, String coin, String price);

  /// No description provided for @ledgerSummaryOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get ledgerSummaryOrder;

  /// No description provided for @ledgerSummaryReduceOnly.
  ///
  /// In en, this message translates to:
  /// **'Reduce only'**
  String get ledgerSummaryReduceOnly;

  /// No description provided for @ledgerSummaryTrailingDistance.
  ///
  /// In en, this message translates to:
  /// **'Trailing distance'**
  String get ledgerSummaryTrailingDistance;

  /// No description provided for @ledgerSummaryActivation.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get ledgerSummaryActivation;

  /// No description provided for @ledgerSummaryImmediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get ledgerSummaryImmediately;

  /// No description provided for @ledgerSummaryActivationFeeMax.
  ///
  /// In en, this message translates to:
  /// **'Network activation fee (maximum)'**
  String get ledgerSummaryActivationFeeMax;

  /// No description provided for @ledgerActionMakeFundsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Make funds available for withdrawal'**
  String get ledgerActionMakeFundsAvailable;

  /// No description provided for @ledgerActionWithdrawToBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Withdraw to your Ledger Bitcoin wallet'**
  String get ledgerActionWithdrawToBitcoin;

  /// No description provided for @ledgerTrailingStopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{side} · Trailing stop · {size}'**
  String ledgerTrailingStopSubtitle(String side, String size);

  /// No description provided for @ledgerFiveMinuteMarkets.
  ///
  /// In en, this message translates to:
  /// **'5 Minute Markets'**
  String get ledgerFiveMinuteMarkets;

  /// No description provided for @builderSetAmount.
  ///
  /// In en, this message translates to:
  /// **'Set amount'**
  String get builderSetAmount;

  /// No description provided for @builderOrderNotPlaced.
  ///
  /// In en, this message translates to:
  /// **'The order could not be placed.'**
  String get builderOrderNotPlaced;

  /// No description provided for @builderBetNotPlaced.
  ///
  /// In en, this message translates to:
  /// **'The prediction could not be placed.'**
  String get builderBetNotPlaced;

  /// No description provided for @builderMarketGone.
  ///
  /// In en, this message translates to:
  /// **'This market is no longer available.'**
  String get builderMarketGone;

  /// No description provided for @builderStepBuild.
  ///
  /// In en, this message translates to:
  /// **'Build portfolio'**
  String get builderStepBuild;

  /// No description provided for @builderStepAmounts.
  ///
  /// In en, this message translates to:
  /// **'Set amounts'**
  String get builderStepAmounts;

  /// No description provided for @builderStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review and place'**
  String get builderStepReview;

  /// No description provided for @builderClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get builderClearSearch;

  /// No description provided for @builderSearchCoinsStocks.
  ///
  /// In en, this message translates to:
  /// **'Search coins and stocks'**
  String get builderSearchCoinsStocks;

  /// No description provided for @builderNoMarketsNow.
  ///
  /// In en, this message translates to:
  /// **'No markets right now.'**
  String get builderNoMarketsNow;

  /// No description provided for @builderNoMarketsFound.
  ///
  /// In en, this message translates to:
  /// **'No markets found.'**
  String get builderNoMarketsFound;

  /// No description provided for @builderMarketsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Markets could not be loaded. Try again later.'**
  String get builderMarketsLoadFailed;

  /// No description provided for @builderSelectMarkets.
  ///
  /// In en, this message translates to:
  /// **'Select markets'**
  String get builderSelectMarkets;

  /// No description provided for @builderContinueSelected.
  ///
  /// In en, this message translates to:
  /// **'Continue · {count} selected'**
  String builderContinueSelected(int count);

  /// No description provided for @builderChooseMarkets.
  ///
  /// In en, this message translates to:
  /// **'Choose markets to build your portfolio.'**
  String get builderChooseMarkets;

  /// No description provided for @builderReviewPortfolio.
  ///
  /// In en, this message translates to:
  /// **'Review portfolio'**
  String get builderReviewPortfolio;

  /// No description provided for @builderEditAmountSemantics.
  ///
  /// In en, this message translates to:
  /// **'Edit amount, {amount}'**
  String builderEditAmountSemantics(String amount);

  /// No description provided for @builderBuySpot.
  ///
  /// In en, this message translates to:
  /// **'Buy {coin} · Spot'**
  String builderBuySpot(String coin);

  /// No description provided for @builderRemoveMarket.
  ///
  /// In en, this message translates to:
  /// **'Remove market'**
  String get builderRemoveMarket;

  /// No description provided for @builderFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed. See details above.'**
  String builderFailedCount(int count);

  /// No description provided for @builderAllPlaced.
  ///
  /// In en, this message translates to:
  /// **'Everything was placed.'**
  String get builderAllPlaced;

  /// No description provided for @builderAddToContinue.
  ///
  /// In en, this message translates to:
  /// **'Add {amount} to continue.'**
  String builderAddToContinue(String amount);

  /// No description provided for @builderPlacingProgress.
  ///
  /// In en, this message translates to:
  /// **'Placing {done} of {total}'**
  String builderPlacingProgress(int done, int total);

  /// No description provided for @builderDoneOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String builderDoneOfTotal(int done, int total);

  /// No description provided for @builderDepositTo.
  ///
  /// In en, this message translates to:
  /// **'Deposit to {pool}'**
  String builderDepositTo(String pool);

  /// No description provided for @builderPlacePredictions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Place 1 prediction} other{Place {count} predictions}}'**
  String builderPlacePredictions(int count);

  /// No description provided for @builderPlaceOrders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Place 1 order} other{Place {count} orders}}'**
  String builderPlaceOrders(int count);

  /// No description provided for @builderAvailableIn.
  ///
  /// In en, this message translates to:
  /// **'{amount} available in {pool}'**
  String builderAvailableIn(String amount, String pool);

  /// No description provided for @importEnterXpub.
  ///
  /// In en, this message translates to:
  /// **'Please enter an xPub'**
  String get importEnterXpub;

  /// No description provided for @importInvalidXpub.
  ///
  /// In en, this message translates to:
  /// **'Invalid Extended Public Key format'**
  String get importInvalidXpub;

  /// No description provided for @importAlreadyImported.
  ///
  /// In en, this message translates to:
  /// **'This wallet is already imported as \"{name}\"'**
  String importAlreadyImported(String name);

  /// No description provided for @importEnterAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter a Bitcoin address'**
  String get importEnterAddress;

  /// No description provided for @importInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid Bitcoin address format'**
  String get importInvalidAddress;

  /// No description provided for @pdfNotTaxShort.
  ///
  /// In en, this message translates to:
  /// **'Not a tax document. For personal orientation only.'**
  String get pdfNotTaxShort;

  /// No description provided for @pdfPage.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String pdfPage(String number);

  /// No description provided for @pdfPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {number} of {count}'**
  String pdfPageOf(String number, String count);

  /// No description provided for @pdfTotalReceived.
  ///
  /// In en, this message translates to:
  /// **'Total received'**
  String get pdfTotalReceived;

  /// No description provided for @pdfTotalSent.
  ///
  /// In en, this message translates to:
  /// **'Total sent'**
  String get pdfTotalSent;

  /// No description provided for @pdfNetFlow.
  ///
  /// In en, this message translates to:
  /// **'Net flow'**
  String get pdfNetFlow;

  /// No description provided for @pdfOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get pdfOpeningBalance;

  /// No description provided for @pdfBefore.
  ///
  /// In en, this message translates to:
  /// **'Before {date}'**
  String pdfBefore(String date);

  /// No description provided for @pdfStartOfHistory.
  ///
  /// In en, this message translates to:
  /// **'Start of history'**
  String get pdfStartOfHistory;

  /// No description provided for @pdfClosingBalance.
  ///
  /// In en, this message translates to:
  /// **'Closing balance'**
  String get pdfClosingBalance;

  /// No description provided for @pdfOpeningPlusNet.
  ///
  /// In en, this message translates to:
  /// **'Opening plus net flow'**
  String get pdfOpeningPlusNet;

  /// No description provided for @pdfFeesPaid.
  ///
  /// In en, this message translates to:
  /// **'Fees paid'**
  String get pdfFeesPaid;

  /// No description provided for @pdfPlusVenueFees.
  ///
  /// In en, this message translates to:
  /// **'Plus {amount} venue fees'**
  String pdfPlusVenueFees(String amount);

  /// No description provided for @pdfInvestingRealizedPnl.
  ///
  /// In en, this message translates to:
  /// **'Investing realized PnL'**
  String get pdfInvestingRealizedPnl;

  /// No description provided for @pdfPredictionsNet.
  ///
  /// In en, this message translates to:
  /// **'Predictions net'**
  String get pdfPredictionsNet;

  /// No description provided for @pdfSellsClaimsMinusBets.
  ///
  /// In en, this message translates to:
  /// **'Sells and claims minus predictions placed'**
  String get pdfSellsClaimsMinusBets;

  /// No description provided for @pdfPredictionsClaimed.
  ///
  /// In en, this message translates to:
  /// **'Predictions claimed'**
  String get pdfPredictionsClaimed;

  /// No description provided for @pdfPlacedInBets.
  ///
  /// In en, this message translates to:
  /// **'{amount} placed in predictions'**
  String pdfPlacedInBets(String amount);

  /// No description provided for @pdfLargestTransaction.
  ///
  /// In en, this message translates to:
  /// **'Largest transaction'**
  String get pdfLargestTransaction;

  /// No description provided for @pdfSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get pdfSummary;

  /// No description provided for @pdfSummaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Period totals, balances, fees and realized results'**
  String get pdfSummaryDesc;

  /// No description provided for @pdfYearlyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Yearly breakdown'**
  String get pdfYearlyBreakdown;

  /// No description provided for @pdfYearlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Annual and quarterly totals by category'**
  String get pdfYearlyDesc;

  /// No description provided for @pdfPortfolioOverview.
  ///
  /// In en, this message translates to:
  /// **'Portfolio overview'**
  String get pdfPortfolioOverview;

  /// No description provided for @pdfPortfolioDesc.
  ///
  /// In en, this message translates to:
  /// **'Wallet allocation and transaction type distribution'**
  String get pdfPortfolioDesc;

  /// No description provided for @pdfActivityAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Activity analysis'**
  String get pdfActivityAnalysis;

  /// No description provided for @pdfActivityDesc.
  ///
  /// In en, this message translates to:
  /// **'Volume patterns and key metrics'**
  String get pdfActivityDesc;

  /// No description provided for @pdfActivityLedger.
  ///
  /// In en, this message translates to:
  /// **'Activity ledger'**
  String get pdfActivityLedger;

  /// No description provided for @pdfLedgerDesc.
  ///
  /// In en, this message translates to:
  /// **'Per-venue tables of every entry in the period'**
  String get pdfLedgerDesc;

  /// No description provided for @pdfActivityReport.
  ///
  /// In en, this message translates to:
  /// **'Activity report'**
  String get pdfActivityReport;

  /// No description provided for @pdfPeriodRange.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String pdfPeriodRange(String from, String to);

  /// No description provided for @pdfGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get pdfGenerated;

  /// No description provided for @pdfWallets.
  ///
  /// In en, this message translates to:
  /// **'Wallets'**
  String get pdfWallets;

  /// No description provided for @pdfTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get pdfTransactions;

  /// No description provided for @pdfDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get pdfDays;

  /// No description provided for @pdfBtcPrice.
  ///
  /// In en, this message translates to:
  /// **'BTC price'**
  String get pdfBtcPrice;

  /// No description provided for @pdfExecutiveSummary.
  ///
  /// In en, this message translates to:
  /// **'Executive summary'**
  String get pdfExecutiveSummary;

  /// No description provided for @pdfContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get pdfContents;

  /// No description provided for @pdfCoversOne.
  ///
  /// In en, this message translates to:
  /// **'Covers {venue}.'**
  String pdfCoversOne(String venue);

  /// No description provided for @pdfCoversMany.
  ///
  /// In en, this message translates to:
  /// **'Covers {list} and {last}.'**
  String pdfCoversMany(String list, String last);

  /// No description provided for @pdfYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get pdfYear;

  /// No description provided for @pdfReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get pdfReceived;

  /// No description provided for @pdfReceivedUsd.
  ///
  /// In en, this message translates to:
  /// **'Received (USD)'**
  String get pdfReceivedUsd;

  /// No description provided for @pdfSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get pdfSent;

  /// No description provided for @pdfSentUsd.
  ///
  /// In en, this message translates to:
  /// **'Sent (USD)'**
  String get pdfSentUsd;

  /// No description provided for @pdfTxs.
  ///
  /// In en, this message translates to:
  /// **'Txs'**
  String get pdfTxs;

  /// No description provided for @pdfCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get pdfCategory;

  /// No description provided for @pdfValueUsd.
  ///
  /// In en, this message translates to:
  /// **'Value (USD)'**
  String get pdfValueUsd;

  /// No description provided for @pdfShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get pdfShare;

  /// No description provided for @pdfAnnualSummary.
  ///
  /// In en, this message translates to:
  /// **'Annual summary'**
  String get pdfAnnualSummary;

  /// No description provided for @pdfQuarterlyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Quarterly breakdown ({year})'**
  String pdfQuarterlyBreakdown(String year);

  /// No description provided for @pdfCategoryBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Category breakdown'**
  String get pdfCategoryBreakdown;

  /// No description provided for @pdfNotTaxTitle.
  ///
  /// In en, this message translates to:
  /// **'Not a tax document'**
  String get pdfNotTaxTitle;

  /// No description provided for @pdfTaxAdvice.
  ///
  /// In en, this message translates to:
  /// **'Consult a qualified tax professional for guidance on reporting requirements in your jurisdiction. Transaction values shown may not reflect the exact fiat value at the time of each transaction.'**
  String get pdfTaxAdvice;

  /// No description provided for @pdfNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity'**
  String get pdfNoActivity;

  /// No description provided for @pdfNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get pdfNet;

  /// No description provided for @pdfWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get pdfWallet;

  /// No description provided for @pdfAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String pdfAsOf(String date);

  /// No description provided for @pdfWalletAllocation.
  ///
  /// In en, this message translates to:
  /// **'Wallet allocation'**
  String get pdfWalletAllocation;

  /// No description provided for @pdfTransactionTypes.
  ///
  /// In en, this message translates to:
  /// **'Transaction types'**
  String get pdfTransactionTypes;

  /// No description provided for @pdfWalletBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Wallet breakdown'**
  String get pdfWalletBreakdown;

  /// No description provided for @pdfType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get pdfType;

  /// No description provided for @pdfBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get pdfBalance;

  /// No description provided for @pdfAllocation.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get pdfAllocation;

  /// No description provided for @pdfWalletTracked.
  ///
  /// In en, this message translates to:
  /// **'Tracked'**
  String get pdfWalletTracked;

  /// No description provided for @pdfWalletHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get pdfWalletHardware;

  /// No description provided for @pdfWalletWatchOnly.
  ///
  /// In en, this message translates to:
  /// **'Watch-Only'**
  String get pdfWalletWatchOnly;

  /// No description provided for @pdfWalletStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pdfWalletStandard;

  /// No description provided for @pdfKeyMetrics.
  ///
  /// In en, this message translates to:
  /// **'Key metrics'**
  String get pdfKeyMetrics;

  /// No description provided for @pdfMostActiveWallet.
  ///
  /// In en, this message translates to:
  /// **'Most active wallet'**
  String get pdfMostActiveWallet;

  /// No description provided for @pdfMostActiveMonth.
  ///
  /// In en, this message translates to:
  /// **'Most active month'**
  String get pdfMostActiveMonth;

  /// No description provided for @pdfLargestReceive.
  ///
  /// In en, this message translates to:
  /// **'Largest receive'**
  String get pdfLargestReceive;

  /// No description provided for @pdfLargestSend.
  ///
  /// In en, this message translates to:
  /// **'Largest send'**
  String get pdfLargestSend;

  /// No description provided for @pdfMedianTx.
  ///
  /// In en, this message translates to:
  /// **'Median tx size'**
  String get pdfMedianTx;

  /// No description provided for @pdfActiveMonths.
  ///
  /// In en, this message translates to:
  /// **'Active months'**
  String get pdfActiveMonths;

  /// No description provided for @pdfActivityByDay.
  ///
  /// In en, this message translates to:
  /// **'Activity by day'**
  String get pdfActivityByDay;

  /// No description provided for @pdfLedgerIntro.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}. Swap and bank orders show both assets; their settlement transfers appear separately.'**
  String pdfLedgerIntro(String from, String to);

  /// No description provided for @pdfLedgerContinued.
  ///
  /// In en, this message translates to:
  /// **'Activity ledger (continued)'**
  String get pdfLedgerContinued;

  /// No description provided for @pdfDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get pdfDate;

  /// No description provided for @pdfMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get pdfMarket;

  /// No description provided for @pdfDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get pdfDetails;

  /// No description provided for @pdfAmountUsd.
  ///
  /// In en, this message translates to:
  /// **'Amount (USD)'**
  String get pdfAmountUsd;

  /// No description provided for @pdfAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get pdfAmount;

  /// No description provided for @pdfRealizedPnl.
  ///
  /// In en, this message translates to:
  /// **'Realized PnL'**
  String get pdfRealizedPnl;

  /// No description provided for @pdfFiatUsd.
  ///
  /// In en, this message translates to:
  /// **'Fiat (USD)'**
  String get pdfFiatUsd;

  /// No description provided for @pdfFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get pdfFee;

  /// No description provided for @pdfStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get pdfStatus;

  /// No description provided for @pdfNoBalanceData.
  ///
  /// In en, this message translates to:
  /// **'No balance data'**
  String get pdfNoBalanceData;

  /// No description provided for @pdfWeekdaysShort.
  ///
  /// In en, this message translates to:
  /// **'Mon,Tue,Wed,Thu,Fri,Sat,Sun'**
  String get pdfWeekdaysShort;

  /// No description provided for @pdfVenueInvesting.
  ///
  /// In en, this message translates to:
  /// **'Investing (Hyperliquid)'**
  String get pdfVenueInvesting;

  /// No description provided for @pdfVenuePredictions.
  ///
  /// In en, this message translates to:
  /// **'Predictions (Polymarket)'**
  String get pdfVenuePredictions;

  /// No description provided for @pdfOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get pdfOther;

  /// No description provided for @pdfRowSent.
  ///
  /// In en, this message translates to:
  /// **'{rail} Sent'**
  String pdfRowSent(String rail);

  /// No description provided for @pdfRowReceived.
  ///
  /// In en, this message translates to:
  /// **'{rail} Received'**
  String pdfRowReceived(String rail);

  /// No description provided for @pdfRowPurchase.
  ///
  /// In en, this message translates to:
  /// **'{provider} Purchase'**
  String pdfRowPurchase(String provider);

  /// No description provided for @pdfRowSwap.
  ///
  /// In en, this message translates to:
  /// **'{provider} Swap'**
  String pdfRowSwap(String provider);

  /// No description provided for @pdfRowUnclaimedDeposit.
  ///
  /// In en, this message translates to:
  /// **'Unclaimed Deposit'**
  String get pdfRowUnclaimedDeposit;

  /// No description provided for @pdfRowBankPurchase.
  ///
  /// In en, this message translates to:
  /// **'Bank Purchase'**
  String get pdfRowBankPurchase;

  /// No description provided for @pdfRowBankWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Bank Withdrawal'**
  String get pdfRowBankWithdrawal;

  /// No description provided for @pdfRowBitcoinDeposit.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Deposit'**
  String get pdfRowBitcoinDeposit;

  /// No description provided for @pdfRowPredictionsReceived.
  ///
  /// In en, this message translates to:
  /// **'Predictions Received'**
  String get pdfRowPredictionsReceived;

  /// No description provided for @pdfRowPredictionsDeposit.
  ///
  /// In en, this message translates to:
  /// **'Predictions Deposit'**
  String get pdfRowPredictionsDeposit;

  /// No description provided for @pdfRowPredictionsWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Predictions Withdrawal'**
  String get pdfRowPredictionsWithdrawal;

  /// No description provided for @pdfRowPredictionsBuy.
  ///
  /// In en, this message translates to:
  /// **'Predictions Buy'**
  String get pdfRowPredictionsBuy;

  /// No description provided for @pdfRowPredictionsSell.
  ///
  /// In en, this message translates to:
  /// **'Predictions Sell'**
  String get pdfRowPredictionsSell;

  /// No description provided for @pdfRowPredictionsClaim.
  ///
  /// In en, this message translates to:
  /// **'Predictions Claim'**
  String get pdfRowPredictionsClaim;

  /// No description provided for @pdfCatExchange.
  ///
  /// In en, this message translates to:
  /// **'Exchange'**
  String get pdfCatExchange;

  /// No description provided for @pdfStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get pdfStatusConfirmed;

  /// No description provided for @pdfStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pdfStatusPending;

  /// No description provided for @pdfStatusUnclaimed.
  ///
  /// In en, this message translates to:
  /// **'Unclaimed'**
  String get pdfStatusUnclaimed;

  /// No description provided for @pdfStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get pdfStatusCompleted;

  /// No description provided for @pdfStatusFilled.
  ///
  /// In en, this message translates to:
  /// **'Filled'**
  String get pdfStatusFilled;

  /// No description provided for @pdfStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pdfStatusFailed;

  /// No description provided for @pdfFillsFees.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 fill} other{{count} fills}}, {fees} fees'**
  String pdfFillsFees(int count, String fees);

  /// No description provided for @pdfEntriesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String pdfEntriesCount(int count);

  /// No description provided for @pdfBtcPriceSuffix.
  ///
  /// In en, this message translates to:
  /// **'. BTC price {price}'**
  String pdfBtcPriceSuffix(String price);

  /// No description provided for @pdfTxCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tx} other{{count} txs}}'**
  String pdfTxCount(int count);

  /// No description provided for @pdfEntriesNet.
  ///
  /// In en, this message translates to:
  /// **'{entries}, net {net}'**
  String pdfEntriesNet(String entries, String net);

  /// No description provided for @pdfDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This report is for personal orientation only. It is not a tax document and may be incomplete or inaccurate.'**
  String get pdfDisclaimer;

  /// No description provided for @pdfShareSubject.
  ///
  /// In en, this message translates to:
  /// **'kute activity report. {disclaimer}'**
  String pdfShareSubject(String disclaimer);

  /// No description provided for @hlChartRangeMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get hlChartRangeMax;

  /// No description provided for @hlBookPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get hlBookPrice;

  /// No description provided for @hlBookSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get hlBookSize;

  /// No description provided for @hl24hHigh.
  ///
  /// In en, this message translates to:
  /// **'24h High'**
  String get hl24hHigh;

  /// No description provided for @hl24hLow.
  ///
  /// In en, this message translates to:
  /// **'24h Low'**
  String get hl24hLow;

  /// No description provided for @hl24hVolume.
  ///
  /// In en, this message translates to:
  /// **'24h Volume'**
  String get hl24hVolume;

  /// No description provided for @hlFundingIn.
  ///
  /// In en, this message translates to:
  /// **'in {minutes}m'**
  String hlFundingIn(int minutes);

  /// No description provided for @hlWideSpreadAck.
  ///
  /// In en, this message translates to:
  /// **'I understand this market has a very wide spread right now.'**
  String get hlWideSpreadAck;

  /// No description provided for @hlTwapOver.
  ///
  /// In en, this message translates to:
  /// **'TWAP · {size} over {minutes}m'**
  String hlTwapOver(String size, int minutes);

  /// No description provided for @ledgerNoPositionsYet.
  ///
  /// In en, this message translates to:
  /// **'No positions yet'**
  String get ledgerNoPositionsYet;

  /// No description provided for @pdfFooterTagline.
  ///
  /// In en, this message translates to:
  /// **'kute. Self-custodial Bitcoin wallet.'**
  String get pdfFooterTagline;

  /// No description provided for @psbtShareText.
  ///
  /// In en, this message translates to:
  /// **'Sign this transaction'**
  String get psbtShareText;

  /// Send dollars, recipient step: the entered address is recognised but no dollar send route or allowed network reaches it.
  ///
  /// In en, this message translates to:
  /// **'Dollars can\'t be sent to this address.'**
  String get usdSendAddressUnsupported;

  /// Send dollars, destination row subtitle when the recipient gets another coin.
  ///
  /// In en, this message translates to:
  /// **'Converted from your dollars'**
  String get usdSendConvertedFromDollars;

  /// No description provided for @polyPillTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get polyPillTrending;

  /// No description provided for @polyPillBreaking.
  ///
  /// In en, this message translates to:
  /// **'Breaking'**
  String get polyPillBreaking;

  /// No description provided for @polyPillNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get polyPillNew;

  /// No description provided for @polyPillLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get polyPillLive;

  /// No description provided for @polyPillPolitics.
  ///
  /// In en, this message translates to:
  /// **'Politics'**
  String get polyPillPolitics;

  /// No description provided for @polyPillSports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get polyPillSports;

  /// No description provided for @polyPillCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get polyPillCrypto;

  /// No description provided for @polyPillEconomy.
  ///
  /// In en, this message translates to:
  /// **'Economy'**
  String get polyPillEconomy;

  /// No description provided for @polyPillWorld.
  ///
  /// In en, this message translates to:
  /// **'World'**
  String get polyPillWorld;

  /// No description provided for @polyPillMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get polyPillMore;

  /// No description provided for @polySubAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get polySubAll;

  /// No description provided for @polySub5m.
  ///
  /// In en, this message translates to:
  /// **'5 Min'**
  String get polySub5m;

  /// No description provided for @polySub15m.
  ///
  /// In en, this message translates to:
  /// **'15 Min'**
  String get polySub15m;

  /// No description provided for @polySub1h.
  ///
  /// In en, this message translates to:
  /// **'1 Hour'**
  String get polySub1h;

  /// No description provided for @polySub4h.
  ///
  /// In en, this message translates to:
  /// **'4 Hours'**
  String get polySub4h;

  /// No description provided for @polySubDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get polySubDaily;

  /// No description provided for @polySubWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get polySubWeekly;

  /// No description provided for @polySubMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get polySubMonthly;

  /// No description provided for @polySubYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get polySubYearly;

  /// No description provided for @polySubPreMarket.
  ///
  /// In en, this message translates to:
  /// **'Pre-Market'**
  String get polySubPreMarket;

  /// No description provided for @polySubFutures.
  ///
  /// In en, this message translates to:
  /// **'Futures'**
  String get polySubFutures;

  /// No description provided for @polySubFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get polySubFinance;

  /// No description provided for @polyPillEsports.
  ///
  /// In en, this message translates to:
  /// **'Esports'**
  String get polyPillEsports;

  /// No description provided for @polyPillGeopolitics.
  ///
  /// In en, this message translates to:
  /// **'Geopolitics'**
  String get polyPillGeopolitics;

  /// No description provided for @polyPillTech.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get polyPillTech;

  /// No description provided for @polyPillCulture.
  ///
  /// In en, this message translates to:
  /// **'Culture'**
  String get polyPillCulture;

  /// No description provided for @polyPillWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get polyPillWeather;

  /// No description provided for @polyPillMentions.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get polyPillMentions;

  /// No description provided for @polyPillElections.
  ///
  /// In en, this message translates to:
  /// **'Elections'**
  String get polyPillElections;

  /// No description provided for @polySubTargets.
  ///
  /// In en, this message translates to:
  /// **'Targets'**
  String get polySubTargets;

  /// No description provided for @polySubInstitutions.
  ///
  /// In en, this message translates to:
  /// **'Institutions'**
  String get polySubInstitutions;

  /// No description provided for @polySubIndustry.
  ///
  /// In en, this message translates to:
  /// **'Industry'**
  String get polySubIndustry;

  /// No description provided for @polySubProtocolMetrics.
  ///
  /// In en, this message translates to:
  /// **'Protocol Metrics'**
  String get polySubProtocolMetrics;

  /// No description provided for @polySubStocks.
  ///
  /// In en, this message translates to:
  /// **'Stocks'**
  String get polySubStocks;

  /// No description provided for @polySubEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get polySubEarnings;

  /// No description provided for @polySubIndices.
  ///
  /// In en, this message translates to:
  /// **'Indices'**
  String get polySubIndices;

  /// No description provided for @polySubCommodities.
  ///
  /// In en, this message translates to:
  /// **'Commodities'**
  String get polySubCommodities;

  /// No description provided for @polySubForex.
  ///
  /// In en, this message translates to:
  /// **'Forex'**
  String get polySubForex;

  /// No description provided for @polySubPrivates.
  ///
  /// In en, this message translates to:
  /// **'Privates'**
  String get polySubPrivates;

  /// No description provided for @polySubAcquisitions.
  ///
  /// In en, this message translates to:
  /// **'Acquisitions'**
  String get polySubAcquisitions;

  /// No description provided for @polySubIpos.
  ///
  /// In en, this message translates to:
  /// **'IPOs'**
  String get polySubIpos;

  /// No description provided for @polySubFedRates.
  ///
  /// In en, this message translates to:
  /// **'Fed Rates'**
  String get polySubFedRates;

  /// No description provided for @polySubPredictionMarkets.
  ///
  /// In en, this message translates to:
  /// **'Prediction Markets'**
  String get polySubPredictionMarkets;

  /// No description provided for @polySubTreasuries.
  ///
  /// In en, this message translates to:
  /// **'Treasuries'**
  String get polySubTreasuries;

  /// No description provided for @polySubKpis.
  ///
  /// In en, this message translates to:
  /// **'KPIs'**
  String get polySubKpis;

  /// No description provided for @polySubTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get polySubTemperature;

  /// No description provided for @polySubPrecipitation.
  ///
  /// In en, this message translates to:
  /// **'Precipitation'**
  String get polySubPrecipitation;

  /// No description provided for @polySubDrought.
  ///
  /// In en, this message translates to:
  /// **'Drought'**
  String get polySubDrought;

  /// No description provided for @polySubGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get polySubGlobal;

  /// No description provided for @polySubTornadoes.
  ///
  /// In en, this message translates to:
  /// **'Tornadoes'**
  String get polySubTornadoes;

  /// No description provided for @polySubHurricanes.
  ///
  /// In en, this message translates to:
  /// **'Hurricanes'**
  String get polySubHurricanes;

  /// No description provided for @polySubEarthquakes.
  ///
  /// In en, this message translates to:
  /// **'Earthquakes'**
  String get polySubEarthquakes;

  /// No description provided for @polySubVolcanoes.
  ///
  /// In en, this message translates to:
  /// **'Volcanoes'**
  String get polySubVolcanoes;

  /// No description provided for @polySubPandemics.
  ///
  /// In en, this message translates to:
  /// **'Pandemics'**
  String get polySubPandemics;

  /// No description provided for @polySportSoccer.
  ///
  /// In en, this message translates to:
  /// **'Soccer'**
  String get polySportSoccer;

  /// No description provided for @polySportTennis.
  ///
  /// In en, this message translates to:
  /// **'Tennis'**
  String get polySportTennis;

  /// No description provided for @polySportCricket.
  ///
  /// In en, this message translates to:
  /// **'Cricket'**
  String get polySportCricket;

  /// No description provided for @polySportBasketball.
  ///
  /// In en, this message translates to:
  /// **'Basketball'**
  String get polySportBasketball;

  /// No description provided for @polySportBaseball.
  ///
  /// In en, this message translates to:
  /// **'Baseball'**
  String get polySportBaseball;

  /// No description provided for @polySportFootball.
  ///
  /// In en, this message translates to:
  /// **'Football'**
  String get polySportFootball;

  /// No description provided for @polySportHockey.
  ///
  /// In en, this message translates to:
  /// **'Hockey'**
  String get polySportHockey;

  /// No description provided for @polySportRugby.
  ///
  /// In en, this message translates to:
  /// **'Rugby'**
  String get polySportRugby;

  /// No description provided for @polySportTableTennis.
  ///
  /// In en, this message translates to:
  /// **'Table Tennis'**
  String get polySportTableTennis;

  /// No description provided for @polySportDarts.
  ///
  /// In en, this message translates to:
  /// **'Darts'**
  String get polySportDarts;

  /// No description provided for @polySportHandball.
  ///
  /// In en, this message translates to:
  /// **'Handball'**
  String get polySportHandball;

  /// No description provided for @polySportGolf.
  ///
  /// In en, this message translates to:
  /// **'Golf'**
  String get polySportGolf;

  /// No description provided for @polySportCombat.
  ///
  /// In en, this message translates to:
  /// **'Combat'**
  String get polySportCombat;

  /// No description provided for @polySportMotorsports.
  ///
  /// In en, this message translates to:
  /// **'Motorsports'**
  String get polySportMotorsports;

  /// No description provided for @polySportCycling.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get polySportCycling;

  /// No description provided for @polySportChess.
  ///
  /// In en, this message translates to:
  /// **'Chess'**
  String get polySportChess;

  /// No description provided for @polyMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get polyMoreTitle;

  /// No description provided for @polyStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get polyStatsTitle;

  /// No description provided for @polyStatEnds.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get polyStatEnds;

  /// No description provided for @polyStatEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get polyStatEnded;

  /// No description provided for @polyRulesAndResolution.
  ///
  /// In en, this message translates to:
  /// **'Rules and resolution'**
  String get polyRulesAndResolution;

  /// No description provided for @polyCardMoveToday.
  ///
  /// In en, this message translates to:
  /// **'{move} today'**
  String polyCardMoveToday(String move);

  /// No description provided for @polyCardMoreOutcomes.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String polyCardMoreOutcomes(int count);

  /// No description provided for @polyCardMarkets.
  ///
  /// In en, this message translates to:
  /// **'{count} markets'**
  String polyCardMarkets(int count);

  /// No description provided for @polyCardVolume.
  ///
  /// In en, this message translates to:
  /// **'{amount} vol'**
  String polyCardVolume(String amount);

  /// No description provided for @polyCountSoFar.
  ///
  /// In en, this message translates to:
  /// **'Count so far'**
  String get polyCountSoFar;

  /// No description provided for @polyCountNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get polyCountNow;

  /// No description provided for @polyPillWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get polyPillWatchlist;

  /// No description provided for @polyWatchlistAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to watchlist'**
  String get polyWatchlistAdd;

  /// No description provided for @polyWatchlistRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from watchlist'**
  String get polyWatchlistRemove;

  /// No description provided for @livestreamInMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Playing in the mini player'**
  String get livestreamInMiniPlayer;

  /// No description provided for @polyLivePossession.
  ///
  /// In en, this message translates to:
  /// **'{team} has the ball'**
  String polyLivePossession(String team);

  /// No description provided for @polyMomentumTitle.
  ///
  /// In en, this message translates to:
  /// **'Momentum'**
  String get polyMomentumTitle;

  /// No description provided for @polyPressureLabel.
  ///
  /// In en, this message translates to:
  /// **'Pressure: {team}'**
  String polyPressureLabel(String team);

  /// No description provided for @polyPressureCaption.
  ///
  /// In en, this message translates to:
  /// **'Read from market prices only: win chance up {points} points in {minutes} min with no change in the score.'**
  String polyPressureCaption(String points, String minutes);

  /// No description provided for @polyPressureCaptionTotals.
  ///
  /// In en, this message translates to:
  /// **'Read from market prices only: win chance up {points} points in {minutes} min with no change in the score, and the Over price is rising too.'**
  String polyPressureCaptionTotals(String points, String minutes);

  /// No description provided for @polyMapsEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier maps {score}'**
  String polyMapsEarlier(String score);

  /// No description provided for @polyGameMoneyline.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get polyGameMoneyline;

  /// No description provided for @polyGameSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread'**
  String get polyGameSpread;

  /// No description provided for @polyGameTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get polyGameTotal;

  /// No description provided for @polyMoreMarkets.
  ///
  /// In en, this message translates to:
  /// **'More markets'**
  String get polyMoreMarkets;

  /// No description provided for @polyGroupHalves.
  ///
  /// In en, this message translates to:
  /// **'Halves'**
  String get polyGroupHalves;

  /// No description provided for @polyGroupQuarters.
  ///
  /// In en, this message translates to:
  /// **'Quarters'**
  String get polyGroupQuarters;

  /// No description provided for @polySubStreams.
  ///
  /// In en, this message translates to:
  /// **'Streams'**
  String get polySubStreams;

  /// No description provided for @polyGameInPlayDelay.
  ///
  /// In en, this message translates to:
  /// **'While the game is live, orders wait {seconds}s before they reach the book.'**
  String polyGameInPlayDelay(String seconds);

  /// No description provided for @polyMarkerGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get polyMarkerGoal;

  /// No description provided for @polyMarkerTouchdown.
  ///
  /// In en, this message translates to:
  /// **'TD'**
  String get polyMarkerTouchdown;

  /// No description provided for @polyMarkerFieldGoal.
  ///
  /// In en, this message translates to:
  /// **'FG'**
  String get polyMarkerFieldGoal;

  /// No description provided for @polyMarkerScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get polyMarkerScore;

  /// No description provided for @polyMarkerCorrection.
  ///
  /// In en, this message translates to:
  /// **'Score corrected'**
  String get polyMarkerCorrection;

  /// No description provided for @polyMarkerFinal.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get polyMarkerFinal;

  /// No description provided for @polyMarkerFinalOn.
  ///
  /// In en, this message translates to:
  /// **'Final · {date}'**
  String polyMarkerFinalOn(String date);

  /// No description provided for @polyKickoffToday.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String polyKickoffToday(String time);

  /// No description provided for @polyKickoffTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow {time}'**
  String polyKickoffTomorrow(String time);

  /// No description provided for @polyKickoffStartsInMinutes.
  ///
  /// In en, this message translates to:
  /// **'Starts in {minutes} min'**
  String polyKickoffStartsInMinutes(int minutes);

  /// No description provided for @polyMarkerHalfTime.
  ///
  /// In en, this message translates to:
  /// **'Half-time'**
  String get polyMarkerHalfTime;

  /// No description provided for @polyMarkerSecondHalf.
  ///
  /// In en, this message translates to:
  /// **'2nd half'**
  String get polyMarkerSecondHalf;

  /// No description provided for @polyMarkerFullTime.
  ///
  /// In en, this message translates to:
  /// **'Full time'**
  String get polyMarkerFullTime;

  /// No description provided for @polyMarkerSet.
  ///
  /// In en, this message translates to:
  /// **'Set {number}'**
  String polyMarkerSet(String number);

  /// No description provided for @polyMarkerMap.
  ///
  /// In en, this message translates to:
  /// **'Map {number}'**
  String polyMarkerMap(String number);

  /// No description provided for @polyMarkerMapWon.
  ///
  /// In en, this message translates to:
  /// **'Map {number} won'**
  String polyMarkerMapWon(String number);

  /// No description provided for @polyMarkerMapWonBy.
  ///
  /// In en, this message translates to:
  /// **'Map {number} to {team}'**
  String polyMarkerMapWonBy(String number, String team);

  /// No description provided for @polyMarkerApprox.
  ///
  /// In en, this message translates to:
  /// **'{label} (time approximate)'**
  String polyMarkerApprox(String label);

  /// No description provided for @livestreamMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get livestreamMiniPlayer;

  /// No description provided for @livestreamOnHost.
  ///
  /// In en, this message translates to:
  /// **'Live on {host}'**
  String livestreamOnHost(String host);

  /// No description provided for @livestreamNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing: {title}'**
  String livestreamNowPlaying(String title);

  /// No description provided for @hlPillTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get hlPillTrending;

  /// No description provided for @hlKindAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get hlKindAll;

  /// Portfolio Builder review: switch that turns 2+ prediction legs into one Polymarket combo (parlay).
  ///
  /// In en, this message translates to:
  /// **'Combine into one prediction'**
  String get comboCombineTitle;

  /// Under the combine switch: how a combo pays.
  ///
  /// In en, this message translates to:
  /// **'One amount. Every leg must win, for a bigger payout.'**
  String get comboCombineSubtitle;

  /// Combo stake label (what the user pays, fees included).
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get comboStake;

  /// Combo quote is loading.
  ///
  /// In en, this message translates to:
  /// **'Getting a price'**
  String get comboGettingPrice;

  /// Label for the combo's payout.
  ///
  /// In en, this message translates to:
  /// **'Pays if every leg wins'**
  String get comboPaysIfAllWin;

  /// Label for payout divided by stake.
  ///
  /// In en, this message translates to:
  /// **'Multiplier'**
  String get comboMultiplier;

  /// Countdown until the combo quote expires.
  ///
  /// In en, this message translates to:
  /// **'Price valid for {seconds}s'**
  String comboPriceValidFor(int seconds);

  /// The combo quote expired and a new one is being requested.
  ///
  /// In en, this message translates to:
  /// **'Refreshing the price'**
  String get comboRefreshingPrice;

  /// Button to request a fresh combo quote.
  ///
  /// In en, this message translates to:
  /// **'Get a new price'**
  String get comboGetNewPrice;

  /// No market maker quoted the combo.
  ///
  /// In en, this message translates to:
  /// **'No price for this combo right now. Try another amount or other legs.'**
  String get comboNoPrice;

  /// The combo quote request failed.
  ///
  /// In en, this message translates to:
  /// **'Could not get a price. Try again.'**
  String get comboPriceFailed;

  /// Combo quote rate limit (15 per minute).
  ///
  /// In en, this message translates to:
  /// **'Too many prices asked. Wait a minute and try again.'**
  String get comboTooManyPrices;

  /// Combo confirm button.
  ///
  /// In en, this message translates to:
  /// **'Place combo'**
  String get comboPlace;

  /// Combo filled on chain.
  ///
  /// In en, this message translates to:
  /// **'Combo placed'**
  String get comboPlaced;

  /// After a combo filled.
  ///
  /// In en, this message translates to:
  /// **'Pays {amount} if every leg wins.'**
  String comboPlacedBody(String amount);

  /// The combo was accepted but its outcome is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Your combo is settling. We will keep checking.'**
  String get comboSettling;

  /// The maker declined on last look or execution failed.
  ///
  /// In en, this message translates to:
  /// **'The price was withdrawn before your combo filled. Nothing was spent.'**
  String get comboDeclined;

  /// The fresh quote costs more or pays less than the approved one.
  ///
  /// In en, this message translates to:
  /// **'The price changed. Check the new price and confirm again.'**
  String get comboPriceChanged;

  /// Another combo from this account has no outcome yet.
  ///
  /// In en, this message translates to:
  /// **'An earlier combo is still settling. Try again in a moment.'**
  String get comboStillSettling;

  /// Label of a combo position or activity row.
  ///
  /// In en, this message translates to:
  /// **'Combo · {count} legs'**
  String comboLegsLabel(int count);

  /// Step-up prompt reason for placing one combo.
  ///
  /// In en, this message translates to:
  /// **'Confirm your combo of {count} legs'**
  String stepUpReasonCombo(int count);

  /// Step-up prompt reason for closing a combo early.
  ///
  /// In en, this message translates to:
  /// **'Confirm closing your combo'**
  String get stepUpReasonComboClose;

  /// Section title for combo positions.
  ///
  /// In en, this message translates to:
  /// **'Combos'**
  String get combosTitle;

  /// Combo payout if every remaining leg wins.
  ///
  /// In en, this message translates to:
  /// **'Potential payout'**
  String get comboPotentialPayout;

  /// Estimated value of an open combo (product of the legs' prices).
  ///
  /// In en, this message translates to:
  /// **'Est. value'**
  String get comboEstimatedValue;

  /// Explains that the combo value is an estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimate from the legs\' prices. The exact price shows when you close.'**
  String get comboEstimateNote;

  /// Combo leg progress.
  ///
  /// In en, this message translates to:
  /// **'{settled} of {total} legs settled'**
  String comboLegsSettled(int settled, int total);

  /// Combo leg status.
  ///
  /// In en, this message translates to:
  /// **'Won'**
  String get comboLegWon;

  /// Combo leg status.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get comboLegLost;

  /// Combo leg status.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get comboLegOpen;

  /// Combo leg status: the leg was voided and pays half.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get comboLegVoid;

  /// Combo detail: the list of legs.
  ///
  /// In en, this message translates to:
  /// **'Legs'**
  String get comboLegs;

  /// Combo chart title: the product of the legs' price histories.
  ///
  /// In en, this message translates to:
  /// **'Estimated value over time'**
  String get comboChartEstimate;

  /// The legs' price histories could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'No chart for this combo yet'**
  String get comboChartUnavailable;

  /// Button to sell a combo early.
  ///
  /// In en, this message translates to:
  /// **'Close combo'**
  String get comboClose;

  /// Exact proceeds of closing a combo, after fees.
  ///
  /// In en, this message translates to:
  /// **'You receive {amount}'**
  String comboCloseFor(String amount);

  /// Under the close proceeds.
  ///
  /// In en, this message translates to:
  /// **'Exact amount after fees'**
  String get comboCloseExact;

  /// Combo early close filled.
  ///
  /// In en, this message translates to:
  /// **'Combo closed for {amount}'**
  String comboClosed(String amount);

  /// No quote for selling the combo.
  ///
  /// In en, this message translates to:
  /// **'No one is buying this combo right now. Try again later.'**
  String get comboNoBuyers;

  /// Button to redeem a settled combo.
  ///
  /// In en, this message translates to:
  /// **'Claim {amount}'**
  String comboClaim(String amount);

  /// A combo with a losing leg.
  ///
  /// In en, this message translates to:
  /// **'This combo lost'**
  String get comboLost;

  /// No description provided for @hlOrdersEndedTitle.
  ///
  /// In en, this message translates to:
  /// **'Ended by Hyperliquid'**
  String get hlOrdersEndedTitle;

  /// No description provided for @hlOrderEndedMargin.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: there wasn\'t enough margin to keep it open.'**
  String get hlOrderEndedMargin;

  /// No description provided for @hlOrderEndedReduceOnly.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: it could only shrink a position that is no longer there.'**
  String get hlOrderEndedReduceOnly;

  /// No description provided for @hlOrderEndedSibling.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: its take-profit or stop-loss partner was filled.'**
  String get hlOrderEndedSibling;

  /// No description provided for @hlOrderEndedOiCap.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: this market reached its open-interest limit.'**
  String get hlOrderEndedOiCap;

  /// No description provided for @hlOrderEndedDelisted.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: this market was delisted.'**
  String get hlOrderEndedDelisted;

  /// No description provided for @hlOrderEndedLiquidated.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: the position was liquidated.'**
  String get hlOrderEndedLiquidated;

  /// No description provided for @hlOrderEndedSelfTrade.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: it would have traded against another of your orders.'**
  String get hlOrderEndedSelfTrade;

  /// No description provided for @hlOrderEndedScheduled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by a scheduled cancel.'**
  String get hlOrderEndedScheduled;

  /// No description provided for @hlOrderEndedTriggered.
  ///
  /// In en, this message translates to:
  /// **'Triggered: the price was reached and the order was sent.'**
  String get hlOrderEndedTriggered;

  /// No description provided for @hlOrderEndedRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected by Hyperliquid.'**
  String get hlOrderEndedRejected;

  /// No description provided for @hlOrderEndedOther.
  ///
  /// In en, this message translates to:
  /// **'Ended by Hyperliquid.'**
  String get hlOrderEndedOther;

  /// No description provided for @hlBannerFilled.
  ///
  /// In en, this message translates to:
  /// **'{coin} order filled'**
  String hlBannerFilled(String coin);

  /// No description provided for @hlBannerTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'{coin} take-profit triggered'**
  String hlBannerTakeProfit(String coin);

  /// No description provided for @hlBannerStopLoss.
  ///
  /// In en, this message translates to:
  /// **'{coin} stop-loss triggered'**
  String hlBannerStopLoss(String coin);

  /// No description provided for @hlBannerTriggered.
  ///
  /// In en, this message translates to:
  /// **'{coin} trigger order sent'**
  String hlBannerTriggered(String coin);

  /// No description provided for @hlBannerLiquidated.
  ///
  /// In en, this message translates to:
  /// **'Your {coin} position was liquidated'**
  String hlBannerLiquidated(String coin);

  /// No description provided for @hlBannerLiquidationRisk.
  ///
  /// In en, this message translates to:
  /// **'{coin} is {distance} from its liquidation price ({price}). Add margin or reduce the position.'**
  String hlBannerLiquidationRisk(String coin, String distance, String price);

  /// No description provided for @hlBannerFunding.
  ///
  /// In en, this message translates to:
  /// **'{coin} funding is high: your position pays about {amount} a day.'**
  String hlBannerFunding(String coin, String amount);

  /// No description provided for @hlBannerOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'{coin} order: {reason}'**
  String hlBannerOrderCancelled(String coin, String reason);

  /// No description provided for @hlNextFundingPay.
  ///
  /// In en, this message translates to:
  /// **'Next funding in {time}: you pay about {amount}'**
  String hlNextFundingPay(String time, String amount);

  /// No description provided for @hlNextFundingReceive.
  ///
  /// In en, this message translates to:
  /// **'Next funding in {time}: you receive about {amount}'**
  String hlNextFundingReceive(String time, String amount);

  /// No description provided for @hlMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String hlMinutesShort(int count);

  /// No description provided for @hlBannerTakeProfitNear.
  ///
  /// In en, this message translates to:
  /// **'{coin} is {distance} from your take-profit price ({price}).'**
  String hlBannerTakeProfitNear(String coin, String distance, String price);

  /// No description provided for @hlBannerStopLossNear.
  ///
  /// In en, this message translates to:
  /// **'{coin} is {distance} from your stop-loss price ({price}).'**
  String hlBannerStopLossNear(String coin, String distance, String price);

  /// No description provided for @hlLayerPressure.
  ///
  /// In en, this message translates to:
  /// **'Buy/sell pressure'**
  String get hlLayerPressure;

  /// No description provided for @hlLayerPressureNote.
  ///
  /// In en, this message translates to:
  /// **'Share bought and sold over the last 5 minutes'**
  String get hlLayerPressureNote;

  /// No description provided for @hlLayerBigTrades.
  ///
  /// In en, this message translates to:
  /// **'Big trades'**
  String get hlLayerBigTrades;

  /// No description provided for @hlLayerBigTradesNote.
  ///
  /// In en, this message translates to:
  /// **'Unusually large trades since you opened the chart'**
  String get hlLayerBigTradesNote;

  /// No description provided for @hlLayerFunding.
  ///
  /// In en, this message translates to:
  /// **'Funding flips'**
  String get hlLayerFunding;

  /// No description provided for @hlLayerFundingNote.
  ///
  /// In en, this message translates to:
  /// **'Where funding changed sign'**
  String get hlLayerFundingNote;

  /// No description provided for @hlLayerOi.
  ///
  /// In en, this message translates to:
  /// **'Open interest signal'**
  String get hlLayerOi;

  /// No description provided for @hlLayerOiNote.
  ///
  /// In en, this message translates to:
  /// **'Shown after 10 minutes on the chart, when it moves sharply'**
  String get hlLayerOiNote;

  /// No description provided for @hlLayerCrowd.
  ///
  /// In en, this message translates to:
  /// **'Predictions levels'**
  String get hlLayerCrowd;

  /// No description provided for @hlLayerCrowdNote.
  ///
  /// In en, this message translates to:
  /// **'Chance of reaching a price, from Predictions'**
  String get hlLayerCrowdNote;

  /// No description provided for @hlLayerMacro.
  ///
  /// In en, this message translates to:
  /// **'Fed and inflation dates'**
  String get hlLayerMacro;

  /// No description provided for @hlLayerMacroNote.
  ///
  /// In en, this message translates to:
  /// **'Next Fed decision and US inflation report'**
  String get hlLayerMacroNote;

  /// No description provided for @hlChartCrowdLevel.
  ///
  /// In en, this message translates to:
  /// **'{percent} by {date}'**
  String hlChartCrowdLevel(String percent, String date);

  /// No description provided for @hlChartFedDecision.
  ///
  /// In en, this message translates to:
  /// **'Fed decision'**
  String get hlChartFedDecision;

  /// No description provided for @hlChartUsInflation.
  ///
  /// In en, this message translates to:
  /// **'US inflation'**
  String get hlChartUsInflation;

  /// No description provided for @hlChartFundingPositive.
  ///
  /// In en, this message translates to:
  /// **'Funding +'**
  String get hlChartFundingPositive;

  /// No description provided for @hlChartFundingNegative.
  ///
  /// In en, this message translates to:
  /// **'Funding −'**
  String get hlChartFundingNegative;

  /// No description provided for @hlChartOiRising.
  ///
  /// In en, this message translates to:
  /// **'Open interest rising: {percent} in {minutes} min'**
  String hlChartOiRising(String percent, int minutes);

  /// No description provided for @hlChartOiFalling.
  ///
  /// In en, this message translates to:
  /// **'Open interest falling: {percent} in {minutes} min'**
  String hlChartOiFalling(String percent, int minutes);

  /// No description provided for @hlMarginAdd.
  ///
  /// In en, this message translates to:
  /// **'Add margin'**
  String get hlMarginAdd;

  /// No description provided for @hlMarginRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove margin'**
  String get hlMarginRemove;

  /// No description provided for @hlMarginAddExplain.
  ///
  /// In en, this message translates to:
  /// **'More margin moves the liquidation price further away. It comes from your available cash.'**
  String get hlMarginAddExplain;

  /// No description provided for @hlMarginRemoveExplain.
  ///
  /// In en, this message translates to:
  /// **'Less margin brings the liquidation price closer. It goes back to your available cash.'**
  String get hlMarginRemoveExplain;

  /// No description provided for @hlMarginCanAdd.
  ///
  /// In en, this message translates to:
  /// **'Available: {amount}'**
  String hlMarginCanAdd(String amount);

  /// No description provided for @hlMarginCanRemove.
  ///
  /// In en, this message translates to:
  /// **'Can remove: {amount}'**
  String hlMarginCanRemove(String amount);

  /// No description provided for @hlMarginLeverageAfter.
  ///
  /// In en, this message translates to:
  /// **'Leverage after'**
  String get hlMarginLeverageAfter;

  /// No description provided for @hlMarginTooMuch.
  ///
  /// In en, this message translates to:
  /// **'That\'s more than you can move.'**
  String get hlMarginTooMuch;

  /// No description provided for @hlMarginAdded.
  ///
  /// In en, this message translates to:
  /// **'Margin added'**
  String get hlMarginAdded;

  /// No description provided for @hlMarginRemoved.
  ///
  /// In en, this message translates to:
  /// **'Margin removed'**
  String get hlMarginRemoved;

  /// No description provided for @hlMarginStepUp.
  ///
  /// In en, this message translates to:
  /// **'Change margin on {coin}'**
  String hlMarginStepUp(String coin);

  /// No description provided for @hlPositionMoney.
  ///
  /// In en, this message translates to:
  /// **'Your money in it'**
  String get hlPositionMoney;

  /// Label over the big figure on an open Investing position screen: the money closing the position now gives back (its margin plus the profit or loss), before fees.
  ///
  /// In en, this message translates to:
  /// **'If you close now'**
  String get hlIfYouCloseNow;

  /// Row on an isolated Investing position: the margin the person put in, with any added since, without the profit or loss.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get hlMargin;

  /// One quiet line in the Details sheet of an open Investing position: the Position size row is the notional the leverage controls; the headline is what closing gives back.
  ///
  /// In en, this message translates to:
  /// **'Position size is what your leverage controls, not your money. Closing gives you back your margin plus the profit or loss.'**
  String get hlPositionSizeExplain;

  /// No description provided for @hlLiquidation.
  ///
  /// In en, this message translates to:
  /// **'Liquidation'**
  String get hlLiquidation;

  /// No description provided for @hlLiqAway.
  ///
  /// In en, this message translates to:
  /// **'{percent} away'**
  String hlLiqAway(String percent);

  /// No description provided for @hlNoLiquidationPrice.
  ///
  /// In en, this message translates to:
  /// **'No liquidation price'**
  String get hlNoLiquidationPrice;

  /// No description provided for @hlMarginModeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get hlMarginModeAdd;

  /// No description provided for @hlMarginModeRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get hlMarginModeRemove;

  /// No description provided for @hlMarginAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add margin to {coin}'**
  String hlMarginAddTitle(String coin);

  /// No description provided for @hlMarginRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove margin from {coin}'**
  String hlMarginRemoveTitle(String coin);

  /// No description provided for @hlMarginAddSummary.
  ///
  /// In en, this message translates to:
  /// **'Adds {amount} from your Investing balance to this position.'**
  String hlMarginAddSummary(String amount);

  /// No description provided for @hlMarginRemoveSummary.
  ///
  /// In en, this message translates to:
  /// **'Takes {amount} out of this position back to your Investing balance.'**
  String hlMarginRemoveSummary(String amount);

  /// No description provided for @hlMarginLiqMoves.
  ///
  /// In en, this message translates to:
  /// **'Liquidation price moves from {from} to {to}.'**
  String hlMarginLiqMoves(String from, String to);

  /// No description provided for @hlMarginCashMoves.
  ///
  /// In en, this message translates to:
  /// **'Your Investing balance goes from {from} to {to}.'**
  String hlMarginCashMoves(String from, String to);

  /// No description provided for @hlSlipChangesPosition.
  ///
  /// In en, this message translates to:
  /// **'This also changes the leverage and margin mode of your open {coin} position.'**
  String hlSlipChangesPosition(String coin);

  /// No description provided for @hlSlipOiCapWarning.
  ///
  /// In en, this message translates to:
  /// **'{coin} is at its open-interest limit. Orders that grow a position may be rejected; reducing or closing still works.'**
  String hlSlipOiCapWarning(String coin);

  /// No description provided for @hlRejectTick.
  ///
  /// In en, this message translates to:
  /// **'The price doesn\'t fit this market\'s price steps. Try a rounder price.'**
  String get hlRejectTick;

  /// No description provided for @hlRejectMinNotional.
  ///
  /// In en, this message translates to:
  /// **'Orders must be worth at least \$10.'**
  String get hlRejectMinNotional;

  /// No description provided for @hlRejectReduceOnly.
  ///
  /// In en, this message translates to:
  /// **'This order can only shrink your position, and it would have grown it. The position may already be closed.'**
  String get hlRejectReduceOnly;

  /// No description provided for @hlRejectPostOnly.
  ///
  /// In en, this message translates to:
  /// **'A post-only order can\'t trade straight away. Move the price away from the market.'**
  String get hlRejectPostOnly;

  /// No description provided for @hlRejectNoLiquidity.
  ///
  /// In en, this message translates to:
  /// **'There was nobody to trade with at that price. Try again or allow more slippage.'**
  String get hlRejectNoLiquidity;

  /// No description provided for @hlRejectTpsl.
  ///
  /// In en, this message translates to:
  /// **'The take-profit or stop-loss price is on the wrong side of the current price.'**
  String get hlRejectTpsl;

  /// No description provided for @hlRejectOiCap.
  ///
  /// In en, this message translates to:
  /// **'This market is at its open-interest limit, so growing a position is paused. You can still reduce or close.'**
  String get hlRejectOiCap;

  /// No description provided for @hlRejectOracle.
  ///
  /// In en, this message translates to:
  /// **'That price is too far from the market price.'**
  String get hlRejectOracle;

  /// Line above the Ask Sal opening questions when the screen has no market.
  ///
  /// In en, this message translates to:
  /// **'Explore public markets and learn how things work.'**
  String get salIntroGeneral;

  /// Line above the Ask Sal opening questions. {market} is a public ticker such as BTC.
  ///
  /// In en, this message translates to:
  /// **'Explore {market} and learn how it works.'**
  String salIntroMarket(String market);

  /// Line above the Ask Sal opening questions on a prediction market.
  ///
  /// In en, this message translates to:
  /// **'Explore this market and learn how it works.'**
  String get salIntroThisMarket;

  /// Line above the Ask Sal opening questions on an order slip. {orderType} is salOrderTypeName.
  ///
  /// In en, this message translates to:
  /// **'Learn how {orderType} orders work.'**
  String salIntroOrder(String orderType);

  /// An order type named inside a sentence (salIntroOrder, salChipEduOrderType).
  ///
  /// In en, this message translates to:
  /// **'{type, select, market{market} limit{limit} scale{scale} stopMarket{stop market} stopLimit{stop limit} takeProfitMarket{take profit market} takeProfitLimit{take profit limit} twap{TWAP} other{order}}'**
  String salOrderTypeName(String type);

  /// Ask Sal opening question. {market} is a public ticker such as BTC.
  ///
  /// In en, this message translates to:
  /// **'Why is {market} moving today?'**
  String salChipHlMovingToday(String market);

  /// No description provided for @salChipHlFundingFlip.
  ///
  /// In en, this message translates to:
  /// **'Why is funding negative on {market}?'**
  String salChipHlFundingFlip(String market);

  /// No description provided for @salChipHlFundingExplain.
  ///
  /// In en, this message translates to:
  /// **'How does funding work for {market}?'**
  String salChipHlFundingExplain(String market);

  /// No description provided for @salChipHlProtectPosition.
  ///
  /// In en, this message translates to:
  /// **'How can I protect a position on {market}?'**
  String salChipHlProtectPosition(String market);

  /// No description provided for @salChipHlLiquidationExplain.
  ///
  /// In en, this message translates to:
  /// **'How does liquidation work on {market}?'**
  String salChipHlLiquidationExplain(String market);

  /// No description provided for @salChipHlWhatDrives.
  ///
  /// In en, this message translates to:
  /// **'What drives the price of {market}?'**
  String salChipHlWhatDrives(String market);

  /// No description provided for @salChipHlCompareRelated.
  ///
  /// In en, this message translates to:
  /// **'How does {market} compare with similar markets?'**
  String salChipHlCompareRelated(String market);

  /// Ask Sal opening question on a prediction market screen.
  ///
  /// In en, this message translates to:
  /// **'Why are the odds moving on this market?'**
  String get salChipPmOddsMoving;

  /// No description provided for @salChipPmClosingSoon.
  ///
  /// In en, this message translates to:
  /// **'What happens when this market closes?'**
  String get salChipPmClosingSoon;

  /// No description provided for @salChipPmLiveGame.
  ///
  /// In en, this message translates to:
  /// **'How is the live game moving these odds?'**
  String get salChipPmLiveGame;

  /// No description provided for @salChipPmWhatMovesIt.
  ///
  /// In en, this message translates to:
  /// **'What could move the odds on this market?'**
  String get salChipPmWhatMovesIt;

  /// No description provided for @salChipPmResolutionRules.
  ///
  /// In en, this message translates to:
  /// **'What are the resolution rules for this market?'**
  String get salChipPmResolutionRules;

  /// No description provided for @salChipPmRelatedMarkets.
  ///
  /// In en, this message translates to:
  /// **'Which markets are related to this one?'**
  String get salChipPmRelatedMarkets;

  /// No description provided for @salChipSearchWatchlistNews.
  ///
  /// In en, this message translates to:
  /// **'What\'s the latest news on {market}?'**
  String salChipSearchWatchlistNews(String market);

  /// No description provided for @salChipEduOrderType.
  ///
  /// In en, this message translates to:
  /// **'How does a {orderType} order work for {market}?'**
  String salChipEduOrderType(String orderType, String market);

  /// No description provided for @salChipEduMarketVsLimit.
  ///
  /// In en, this message translates to:
  /// **'How do market and limit orders differ?'**
  String get salChipEduMarketVsLimit;

  /// No description provided for @salChipEduLeverage.
  ///
  /// In en, this message translates to:
  /// **'How does leverage change liquidation risk?'**
  String get salChipEduLeverage;

  /// No description provided for @salChipEduFunding.
  ///
  /// In en, this message translates to:
  /// **'What is funding on a perpetual contract?'**
  String get salChipEduFunding;

  /// No description provided for @salChipEduPredictionBasics.
  ///
  /// In en, this message translates to:
  /// **'How do prediction markets work?'**
  String get salChipEduPredictionBasics;

  /// No description provided for @salChipWalletReceive.
  ///
  /// In en, this message translates to:
  /// **'How do I receive Bitcoin in Kute?'**
  String get salChipWalletReceive;

  /// No description provided for @salChipWalletSend.
  ///
  /// In en, this message translates to:
  /// **'How do I send Bitcoin in Kute?'**
  String get salChipWalletSend;

  /// No description provided for @salChipStocksVsPerps.
  ///
  /// In en, this message translates to:
  /// **'What is the difference between stocks and perps?'**
  String get salChipStocksVsPerps;

  /// No description provided for @salChipRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'What is a recovery phrase?'**
  String get salChipRecoveryPhrase;

  /// No description provided for @salChipBackupHow.
  ///
  /// In en, this message translates to:
  /// **'How does a wallet backup work?'**
  String get salChipBackupHow;

  /// No description provided for @salChipRecoveryPrivate.
  ///
  /// In en, this message translates to:
  /// **'Why should a recovery phrase stay private?'**
  String get salChipRecoveryPrivate;

  /// No description provided for @salChipNetworkConfirmation.
  ///
  /// In en, this message translates to:
  /// **'What is a network confirmation?'**
  String get salChipNetworkConfirmation;

  /// No description provided for @salChipNetworkFees.
  ///
  /// In en, this message translates to:
  /// **'How do Bitcoin network fees work?'**
  String get salChipNetworkFees;

  /// No description provided for @salChipTxPending.
  ///
  /// In en, this message translates to:
  /// **'Why can a transaction stay pending?'**
  String get salChipTxPending;

  /// Second half of the available line under the Invest and Predictions amounts, after a middle dot: the smallest amount the order takes. {amount} is formatted money.
  ///
  /// In en, this message translates to:
  /// **'Minimum {amount}'**
  String amountMinimumInline(String amount);

  /// No description provided for @salSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get salSource;

  /// Investing statistics tile: notional traded (price times size of every fill) in the selected range.
  ///
  /// In en, this message translates to:
  /// **'Volume traded'**
  String get portfolioStatVolume;

  /// Investing statistics tile: number of fills in the selected range, one per execution as the Activity tab counts them.
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get portfolioStatTrades;

  /// The top Deposit button of an Investing (Hyperliquid) surface: Investing tab, Ledger Investing tab. Named like 'Dollar deposit' and shown beside the Hyperliquid mark; 'Investing' is the tab's name.
  ///
  /// In en, this message translates to:
  /// **'Investing deposit'**
  String get investingDeposit;

  /// The top Deposit button of a Predictions (Polymarket) surface: home Predictions card, Predictions tab, Ledger Predictions tab. Named like 'Dollar deposit' and shown beside the Polymarket mark; 'Predictions' is the tab's name.
  ///
  /// In en, this message translates to:
  /// **'Predictions deposit'**
  String get predictionsDeposit;

  /// Title of the Financial hub sheet opened from the + at the top right of the shell's top bar (and from a wallet screen's name): the wallet list, switch wallet, Add wallet, Notifications in its header and a labelled Settings row last. Also the + button's screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'Financial hub'**
  String get walletActionsTitle;

  /// Portfolio Statistics tab, category donut centre under a picked category: its share of the all-time total (amount predicted or volume traded), e.g. "42% of total".
  ///
  /// In en, this message translates to:
  /// **'{percent} of total'**
  String portfolioCategoryShare(String percent);

  /// Tooltip and screen-reader label of the dock's square button (Sal holding a magnifying glass) when Sal is available, and the placeholder of the search sheet's field it opens. Short: it is the one door to both search and Ask Sal.
  ///
  /// In en, this message translates to:
  /// **'Search or ask Sal'**
  String get searchOrAskSalShort;

  /// Screen-reader label of the top bar's right-hand button, whose glyph is a settings gear with a + in its centre. It opens the Financial hub: the accounts, Add account, Notifications in its header and a labelled Settings row last.
  ///
  /// In en, this message translates to:
  /// **'Financial hub and settings'**
  String get financialHubAndSettings;

  /// Analytics strip tab on Home and Dollars: a donut of where the money went (Sent) or came from (Received), all time, by kind.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get analyticsBreakdownTab;

  /// Statistics tab of the Predictions and Investing portfolios: the small pill for what is open now (open positions by category, open P&L, amount at stake, open positions).
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get portfolioStatsActive;

  /// Statistics tab of the Predictions and Investing portfolios: the small pill for the all-time figures (realized P&L, amount predicted or volume traded, count).
  ///
  /// In en, this message translates to:
  /// **'Historic'**
  String get portfolioStatsHistoric;

  /// Statistics tab, Active pill: tile label. Predictions: what the open positions cost. Investing: the margin the open positions use.
  ///
  /// In en, this message translates to:
  /// **'Amount at stake'**
  String get portfolioStatAtStake;

  /// The Investing order button when the person already holds a perp position on this side: the order adds to it. {side} is 'long' or 'short' (select), {amount} is formatted money.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Add to long · {amount}} other{Add to short · {amount}}}'**
  String slipCtaAddTo(String side, String amount);

  /// The Investing order button when an opposite-side order is smaller than the held perp position (Hyperliquid nets one position per market, so it reduces it). {side} is the HELD side, 'long' or 'short' (select); {amount} is formatted money.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Reduce long · {amount}} other{Reduce short · {amount}}}'**
  String slipCtaReduce(String side, String amount);

  /// The Investing order button when an opposite-side order equals the held perp position: it closes it. {side} is the HELD side, 'long' or 'short' (select).
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Close long} other{Close short}}'**
  String slipCtaClose(String side);

  /// The Investing order button when an opposite-side order is larger than the held perp position: it closes it and opens the rest on the new side. {side} is the NEW side, 'long' or 'short' (select); {amount} is formatted money.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Flip to long · {amount}} other{Flip to short · {amount}}}'**
  String slipCtaFlip(String side, String amount);

  /// Quiet line under the Investing amount when the person holds a perp position on the same side. {side} is 'long' or 'short' (select), {size} the held size, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{You hold a long of {size} {coin} — this adds to it} other{You hold a short of {size} {coin} — this adds to it}}'**
  String slipPositionAdds(String side, String size, String coin);

  /// Quiet line under the Investing amount when an opposite-side order reduces the held perp position. {side} is the HELD side (select), {size} the held size, {remaining} the size left after the order, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{You hold a long of {size} {coin} — this reduces it to {remaining} {coin}} other{You hold a short of {size} {coin} — this reduces it to {remaining} {coin}}}'**
  String slipPositionReduces(
      String side, String size, String remaining, String coin);

  /// Quiet line under the Investing amount when an opposite-side order closes the held perp position. {side} is the HELD side (select), {size} the held size, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{You hold a long of {size} {coin} — this closes it} other{You hold a short of {size} {coin} — this closes it}}'**
  String slipPositionCloses(String side, String size, String coin);

  /// Quiet line under the Investing amount when an opposite-side order is larger than the held perp position: it closes it and opens the rest on the other side. {side} is the HELD side (select), {size} the held size, {remainder} the size opened on the other side, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{You hold a long of {size} {coin} — this closes it and opens a short of {remainder} {coin}} other{You hold a short of {size} {coin} — this closes it and opens a long of {remainder} {coin}}}'**
  String slipPositionFlips(
      String side, String size, String remainder, String coin);

  /// Chip on the Investing order-filled receipt when the order added to a perp position already held on its side. {side} is the side, 'long' or 'short' (select).
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Added to long} other{Added to short}}'**
  String hlReceiptAddedTo(String side);

  /// Chip on the Investing order-filled receipt when an opposite-side order reduced the held perp position. {side} is the HELD side, 'long' or 'short' (select); {size} is what is left of the position after the fill, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Reduced long · {size} {coin}} other{Reduced short · {size} {coin}}}'**
  String hlReceiptReduced(String side, String size, String coin);

  /// Chip on the Investing order-filled receipt when an opposite-side order closed the held perp position. {side} is the HELD side, 'long' or 'short' (select).
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Closed long} other{Closed short}}'**
  String hlReceiptClosed(String side);

  /// Chip on the Investing order-filled receipt when an opposite-side order closed the held perp position and opened the rest on the other side. {side} is the NEW side, 'long' or 'short' (select); {size} is the size of the new position, {coin} the market's symbol.
  ///
  /// In en, this message translates to:
  /// **'{side, select, long{Flipped to long · {size} {coin}} other{Flipped to short · {size} {coin}}}'**
  String hlReceiptFlipped(String side, String size, String coin);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'bg',
        'cs',
        'da',
        'de',
        'el',
        'en',
        'es',
        'et',
        'fi',
        'fr',
        'hr',
        'hu',
        'it',
        'ja',
        'lt',
        'lv',
        'nl',
        'pl',
        'pt',
        'ro',
        'sk',
        'sl',
        'sv'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bg':
      return AppLocalizationsBg();
    case 'cs':
      return AppLocalizationsCs();
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'et':
      return AppLocalizationsEt();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'hr':
      return AppLocalizationsHr();
    case 'hu':
      return AppLocalizationsHu();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'lt':
      return AppLocalizationsLt();
    case 'lv':
      return AppLocalizationsLv();
    case 'nl':
      return AppLocalizationsNl();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ro':
      return AppLocalizationsRo();
    case 'sk':
      return AppLocalizationsSk();
    case 'sl':
      return AppLocalizationsSl();
    case 'sv':
      return AppLocalizationsSv();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
