import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/error_handling.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Lnurl Model
  // ---------------------------------------------------------------------------
  group('Lnurl', () {
    test('constructor with all fields', () {
      final lnurl = Lnurl(
        lightningAddress: 'user@domain.com',
        lnurl: 'lnurl1dp68gurn8ghj7...',
        description: 'My lightning address',
        username: 'user',
      );
      expect(lnurl.lightningAddress, 'user@domain.com');
      expect(lnurl.lnurl, 'lnurl1dp68gurn8ghj7...');
      expect(lnurl.description, 'My lightning address');
      expect(lnurl.username, 'user');
    });

    test('constructor with no fields defaults to null', () {
      final lnurl = Lnurl();
      expect(lnurl.lightningAddress, isNull);
      expect(lnurl.lnurl, isNull);
      expect(lnurl.description, isNull);
      expect(lnurl.username, isNull);
    });

    test('constructor with only lightningAddress', () {
      final lnurl = Lnurl(lightningAddress: 'alice@pay.me');
      expect(lnurl.lightningAddress, 'alice@pay.me');
      expect(lnurl.lnurl, isNull);
      expect(lnurl.description, isNull);
      expect(lnurl.username, isNull);
    });

    test('constructor with only username', () {
      final lnurl = Lnurl(username: 'bob');
      expect(lnurl.username, 'bob');
      expect(lnurl.lightningAddress, isNull);
    });

    test('constructor with empty strings', () {
      final lnurl = Lnurl(
        lightningAddress: '',
        lnurl: '',
        description: '',
        username: '',
      );
      expect(lnurl.lightningAddress, '');
      expect(lnurl.lnurl, '');
      expect(lnurl.description, '');
      expect(lnurl.username, '');
    });

    test('lightningAddress with various formats', () {
      // Standard email-like format
      final standard = Lnurl(lightningAddress: 'user@wallet.com');
      expect(standard.lightningAddress, 'user@wallet.com');

      // Subdomain format
      final subdomain = Lnurl(lightningAddress: 'alice@pay.wallet.com');
      expect(subdomain.lightningAddress, 'alice@pay.wallet.com');

      // With numbers
      final withNumbers = Lnurl(lightningAddress: 'user123@domain.io');
      expect(withNumbers.lightningAddress, 'user123@domain.io');
    });

    test('lnurl with long bech32 string', () {
      final longLnurl = 'lnurl1${'a' * 200}';
      final lnurl = Lnurl(lnurl: longLnurl);
      expect(lnurl.lnurl, longLnurl);
    });

    test('description with special characters', () {
      final lnurl = Lnurl(description: 'Pay me! 💰 #bitcoin @user <html>');
      expect(lnurl.description, 'Pay me! 💰 #bitcoin @user <html>');
    });

    test('description with multiline text', () {
      final lnurl = Lnurl(description: 'Line 1\nLine 2\nLine 3');
      expect(lnurl.description, contains('\n'));
    });
  });

  // ---------------------------------------------------------------------------
  // UsernameConflictException
  // ---------------------------------------------------------------------------
  group('UsernameConflictException', () {
    test('stores message', () {
      final ex = UsernameConflictException('username taken');
      expect(ex.message, 'username taken');
    });

    test('toString includes class name and message', () {
      final ex = UsernameConflictException('alice is taken');
      expect(ex.toString(), 'UsernameConflictException: alice is taken');
    });

    test('implements Exception', () {
      final ex = UsernameConflictException('test');
      expect(ex, isA<Exception>());
    });

    test('empty message', () {
      final ex = UsernameConflictException('');
      expect(ex.message, '');
      expect(ex.toString(), 'UsernameConflictException: ');
    });

    test('message with special characters', () {
      final ex = UsernameConflictException("The username 'bob' is already taken.");
      expect(ex.message, "The username 'bob' is already taken.");
    });
  });

  // ---------------------------------------------------------------------------
  // RegisterWebhookException
  // ---------------------------------------------------------------------------
  group('RegisterWebhookException', () {
    test('stores message', () {
      final ex = RegisterWebhookException('webhook failed');
      expect(ex.message, 'webhook failed');
    });

    test('toString includes class name and message', () {
      final ex = RegisterWebhookException('SDK not initialized');
      expect(ex.toString(), 'RegisterWebhookException: SDK not initialized');
    });

    test('implements Exception', () {
      final ex = RegisterWebhookException('test');
      expect(ex, isA<Exception>());
    });

    test('empty message', () {
      final ex = RegisterWebhookException('');
      expect(ex.message, '');
      expect(ex.toString(), 'RegisterWebhookException: ');
    });

    test('message with SDK error details', () {
      final ex = RegisterWebhookException(
        'SdkError.generic(field0: "connection refused")',
      );
      expect(ex.message, contains('connection refused'));
    });
  });

  // ---------------------------------------------------------------------------
  // RegistrationType
  // ---------------------------------------------------------------------------
  group('RegistrationType', () {
    test('newRegistration constant', () {
      expect(RegistrationType.newRegistration, 'newRegistration');
    });

    test('update constant', () {
      expect(RegistrationType.update, 'update');
    });

    test('constants are distinct', () {
      expect(
        RegistrationType.newRegistration,
        isNot(equals(RegistrationType.update)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // handlePaymentException – error parsing via non-SdkError fallback
  // ---------------------------------------------------------------------------
  group('handlePaymentException', () {
    // Helper: calls handlePaymentException and returns the thrown Exception message
    String captureMessage(Object error) {
      try {
        handlePaymentException(error);
      } catch (e) {
        return e.toString();
      }
    }

    // --- Dust limit errors ---
    group('dust limit errors', () {
      test('parses dust error with tuple format extracting minimum sats', () {
        final msg = captureMessage(
          "('Output amount %d sats cannot be smaller than the minimal non dust amount %d sats', 10, 294)",
        );
        expect(msg, contains('Amount is too small'));
        expect(msg, contains('294 sats'));
      });

      test('parses dust error with different minimum value', () {
        final msg = captureMessage(
          "('Output amount %d sats cannot be smaller than the minimal non dust amount %d sats', 5, 546)",
        );
        expect(msg, contains('546 sats'));
      });

      test('dust error without tuple format gives generic dust message', () {
        final msg = captureMessage(
          'Output cannot be smaller than the minimal non dust amount',
        );
        expect(msg, contains('Amount is too small'));
        expect(msg, contains('Bitcoin Dust Limit'));
      });

      test('dust error case insensitive', () {
        final msg = captureMessage(
          'MINIMAL NON DUST AMOUNT exceeded',
        );
        expect(msg, contains('Amount is too small'));
      });

      test('dust error with extra whitespace in tuple', () {
        final msg = captureMessage(
          "('minimal non dust amount', 10,  500 )",
        );
        expect(msg, contains('500 sats'));
      });
    });

    // --- Insufficient funds errors ---
    group('insufficient funds errors', () {
      test('handles "insufficient funds" message', () {
        final msg = captureMessage('insufficient funds for transaction');
        expect(msg, contains('Insufficient balance'));
        expect(msg, contains('tap 100% to send everything'));
      });

      test('handles "insufficient balance" message', () {
        final msg = captureMessage('Error: insufficient balance');
        expect(msg, contains('Insufficient balance'));
      });

      test('insufficient funds case insensitive', () {
        final msg = captureMessage('INSUFFICIENT FUNDS');
        expect(msg, contains('Insufficient balance'));
      });

      test('insufficient funds mixed case', () {
        final msg = captureMessage('Insufficient Funds detected');
        expect(msg, contains('Insufficient balance'));
      });
      // An LNURL / Lightning address pay the balance cannot cover with its
      // fee is refused as SdkError.insufficientFunds: it stays typed, so the
      // send screen answers it by type in the user's language.
      test('the SDK refusal is typed, its text unchanged', () {
        Object? thrown;
        try {
          handlePaymentException(const SdkError.insufficientFunds());
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<SparkInsufficientFundsException>());
        expect(isSparkInsufficientFunds(thrown), isTrue);
        expect(thrown.toString(), contains('Insufficient balance'));
        expect(isSparkInsufficientFunds(const SdkError.insufficientFunds()),
            isTrue);
      });

      test('the same refusal said in words is typed too', () {
        expect(() => handlePaymentException('insufficient funds'),
            throwsA(isA<SparkInsufficientFundsException>()));
        expect(isSparkInsufficientFunds(Exception('route not found')),
            isFalse);
      });
    });

    // --- Route errors ---
    group('route errors', () {
      test('handles "route not found"', () {
        final msg = captureMessage('Payment failed: route not found');
        expect(msg, contains('No route to destination'));
        expect(msg, contains('Recipient might be offline'));
      });

      test('handles "no route"', () {
        final msg = captureMessage('no route available to peer');
        expect(msg, contains('No route to destination'));
      });

      test('route error case insensitive', () {
        final msg = captureMessage('ROUTE NOT FOUND');
        expect(msg, contains('No route to destination'));
      });

      test('no route case insensitive', () {
        final msg = captureMessage('NO ROUTE to node');
        expect(msg, contains('No route to destination'));
      });
    });

    // --- Generic cleanup ---
    group('generic message cleanup', () {
      test('strips "Exception: " prefix', () {
        final msg = captureMessage('Exception: something went wrong');
        expect(msg, contains('something went wrong'));
        // The outer Exception wraps it, so check the inner content
        expect(msg, isNot(contains('Exception: Exception:')));
      });

      test('strips "graphql error: " prefix', () {
        final msg = captureMessage('graphql error: mutation failed');
        expect(msg, contains('mutation failed'));
      });

      test('strips "Service error: service provider error: " prefix', () {
        final msg = captureMessage(
          'Service error: service provider error: timeout',
        );
        expect(msg, contains('timeout'));
      });

      test('passes through clean message unchanged', () {
        final msg = captureMessage('Something unexpected happened');
        expect(msg, contains('Something unexpected happened'));
      });

      test('handles empty string', () {
        final msg = captureMessage('');
        // Should throw an Exception with empty content
        expect(msg, isA<String>());
      });
    });

    // --- Error type handling ---
    group('error type handling', () {
      test('handles plain String errors', () {
        final msg = captureMessage('a plain string error');
        expect(msg, contains('a plain string error'));
      });

      test('handles Exception objects via toString fallback', () {
        final msg = captureMessage(Exception('wrapped message'));
        expect(msg, contains('wrapped message'));
      });

      test('handles FormatException', () {
        final msg = captureMessage(const FormatException('bad format'));
        expect(msg, contains('bad format'));
      });

      test('handles StateError', () {
        final msg = captureMessage(StateError('bad state'));
        expect(msg, contains('bad state'));
      });

      test('handles ArgumentError', () {
        final msg = captureMessage(ArgumentError('invalid arg'));
        expect(msg, contains('invalid arg'));
      });
    });

    // --- Priority / precedence ---
    group('error detection priority', () {
      test('dust limit takes precedence over insufficient funds', () {
        // A message containing both patterns should match dust first
        final msg = captureMessage(
          'insufficient funds: minimal non dust amount is 294, 294)',
        );
        expect(msg, contains('Amount is too small'));
      });

      test('insufficient funds takes precedence over route errors', () {
        final msg = captureMessage(
          'insufficient funds, no route available',
        );
        expect(msg, contains('Insufficient balance'));
      });
    });

    // --- Return type ---
    group('always throws', () {
      test('handlePaymentException always throws an Exception', () {
        expect(
          () => handlePaymentException('any error'),
          throwsA(isA<Exception>()),
        );
      });

      test('never returns normally', () {
        expect(
          () => handlePaymentException('test'),
          throwsException,
        );
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Amount validation edge cases (as relevant to LNURL pay/withdraw)
  // ---------------------------------------------------------------------------
  group('amount validation edge cases', () {
    // These test the dust-limit regex extraction in _throwParsedMessage

    String captureMessage(Object error) {
      try {
        handlePaymentException(error);
      } catch (e) {
        return e.toString();
      }
    }

    test('dust limit with 1 sat minimum', () {
      final msg = captureMessage(
        "('minimal non dust amount', 0, 1)",
      );
      expect(msg, contains('1 sats'));
    });

    test('dust limit with large minimum', () {
      final msg = captureMessage(
        "('minimal non dust amount', 100, 100000)",
      );
      expect(msg, contains('100000 sats'));
    });

    test('dust limit regex does not match without closing paren', () {
      final msg = captureMessage(
        'minimal non dust amount 294',
      );
      // No tuple format -> falls to generic dust message
      expect(msg, contains('Bitcoin Dust Limit'));
    });

    test('zero amount in dust error', () {
      final msg = captureMessage(
        "('minimal non dust amount', 0, 0)",
      );
      expect(msg, contains('0 sats'));
    });
  });

  // ---------------------------------------------------------------------------
  // LNURL parsing edge cases
  // ---------------------------------------------------------------------------
  group('LNURL parsing edge cases', () {
    test('Lnurl with unicode username', () {
      final lnurl = Lnurl(username: 'ユーザー');
      expect(lnurl.username, 'ユーザー');
    });

    test('Lnurl with very long description', () {
      final desc = 'A' * 10000;
      final lnurl = Lnurl(description: desc);
      expect(lnurl.description!.length, 10000);
    });

    test('Lnurl with URL-like lightningAddress', () {
      final lnurl = Lnurl(lightningAddress: 'user@sub.domain.co.uk');
      expect(lnurl.lightningAddress, 'user@sub.domain.co.uk');
    });

    test('Lnurl preserves whitespace in description', () {
      final lnurl = Lnurl(description: '  spaced  out  ');
      expect(lnurl.description, '  spaced  out  ');
    });

    test('Lnurl with null vs empty string distinction', () {
      final withNull = Lnurl(username: null);
      final withEmpty = Lnurl(username: '');
      expect(withNull.username, isNull);
      expect(withEmpty.username, '');
      expect(withNull.username != withEmpty.username, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // LnUrlPayService error mapping logic (tested via exception construction)
  // ---------------------------------------------------------------------------
  group('LnUrlPayService error mapping patterns', () {
    // These tests verify the error-mapping logic that the service uses:
    // if error contains "conflict" or "taken" -> UsernameConflictException
    // otherwise -> RegisterWebhookException

    bool isConflictError(String errorMessage) {
      final lower = errorMessage.toLowerCase();
      return lower.contains('conflict') || lower.contains('taken');
    }

    test('detects "conflict" as username conflict', () {
      expect(isConflictError('409 conflict'), isTrue);
    });

    test('detects "taken" as username conflict', () {
      expect(isConflictError('username already taken'), isTrue);
    });

    test('detects "CONFLICT" case insensitive', () {
      expect(isConflictError('HTTP CONFLICT ERROR'), isTrue);
    });

    test('detects "Taken" case insensitive', () {
      expect(isConflictError('Username Taken'), isTrue);
    });

    test('does not detect unrelated errors as conflict', () {
      expect(isConflictError('network timeout'), isFalse);
    });

    test('does not detect empty string as conflict', () {
      expect(isConflictError(''), isFalse);
    });

    test('does not detect "SDK not initialized" as conflict', () {
      expect(isConflictError('SDK not initialized'), isFalse);
    });

    test('UsernameConflictException preserves username in message', () {
      const username = 'alice';
      final ex = UsernameConflictException(
        "The username '$username' is already taken.",
      );
      expect(ex.message, contains('alice'));
      expect(ex.message, contains('already taken'));
    });

    test('RegisterWebhookException wraps arbitrary error', () {
      final ex = RegisterWebhookException(
        'SdkError.networkError(field0: "DNS resolution failed")',
      );
      expect(ex.message, contains('DNS resolution failed'));
    });
  });

  // ---------------------------------------------------------------------------
  // Error handling combined scenarios
  // ---------------------------------------------------------------------------
  group('handlePaymentException combined scenarios', () {
    String captureMessage(Object error) {
      try {
        handlePaymentException(error);
      } catch (e) {
        return e.toString();
      }
    }

    test('multiple prefix stripping in one message', () {
      final msg = captureMessage(
        'Exception: graphql error: Service error: service provider error: real error',
      );
      // After stripping, should contain the real error
      expect(msg, contains('real error'));
    });

    test('message with only prefix gets cleaned', () {
      final msg = captureMessage('Exception: ');
      // After stripping "Exception: ", left with empty or whitespace
      expect(msg, isA<String>());
    });

    test('handles newlines in error message', () {
      final msg = captureMessage('Error on\nline two');
      expect(msg, contains('Error on'));
    });

    test('handles error with quotes', () {
      final msg = captureMessage("Error: can't process \"payment\"");
      expect(msg, contains("can't process"));
    });

    test('very long error message is capped, not preserved', () {
      // The scrubber caps SDK messages at 120 chars (payload
      // exfiltration guard), so a huge error must come back truncated
      // with an ellipsis rather than verbatim.
      // Upper-case tokens: a run of short lower-case words is redacted
      // whole as a possible recovery phrase (checked below), which would
      // hide the cap this test is about.
      final longError = List.filled(1000, 'ERR').join(' ');
      final msg = captureMessage(longError);
      expect(msg, contains('...'));
      expect(msg.length, lessThan(200));

      final wordRun = List.filled(1000, 'word').join(' ');
      final redacted = captureMessage(wordRun);
      expect(redacted, isNot(contains('word word word')));
      expect(redacted.length, lessThan(200));
    });

    test('long hex blobs are collapsed to <hex>', () {
      final msg = captureMessage('E' * 5000);
      expect(msg, contains('<hex>'));
      expect(msg, isNot(contains('E' * 20)));
    });
  });
}
