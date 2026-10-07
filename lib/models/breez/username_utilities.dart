import 'dart:math';
import 'package:kute/models/breez/lnurl_webhook_manager.dart';

class UsernameResolver {
  final BreezPreferences breezPreferences;

  UsernameResolver(this.breezPreferences);

  Future<String> resolveUsername({
    required String walletId,
    String? recoveredLightningAddress,
    String? baseUsername,
  }) async {
    if (recoveredLightningAddress?.isNotEmpty ?? false) {
      return recoveredLightningAddress!.split('@').first;
    }
    if (baseUsername?.isNotEmpty ?? false) {
      return baseUsername!;
    }
    final storedUsername = await breezPreferences.getLnAddressUsername(walletId);
    if (storedUsername?.isNotEmpty ?? false) {
      return storedUsername!;
    }
    return RandomUsernameGenerator.generate();
  }
}

class RandomUsernameGenerator {
  static final _random = Random.secure();

  static const _adjectives = [
    'agile', 'azure', 'bold', 'brave', 'bright', 'brisk', 'calm', 'chief',
    'clear', 'clever', 'cobalt', 'cool', 'dapper', 'deft', 'eager', 'epic',
    'fabled', 'fast', 'fierce', 'fine', 'firm', 'fresh', 'gentle', 'golden',
    'grand', 'great', 'happy', 'honest', 'humble', 'jolly', 'keen', 'kind',
    'lively', 'loyal', 'lucid', 'major', 'merry', 'neat', 'noble', 'placid',
    'prime', 'proud', 'quick', 'quiet', 'regal', 'sage', 'sharp', 'sleek',
    'sound', 'swift'
  ];

  static const _nouns = [
    'admiral', 'anchor', 'beacon', 'boat', 'captain', 'clipper', 'coast', 'compass',
    'coral', 'cove', 'crew', 'current', 'dawn', 'deck', 'dock', 'expedition',
    'fleet', 'fluke', 'galleon', 'gulf', 'harbor', 'haven', 'horizon', 'island',
    'jetty', 'journey', 'knot', 'lagoon', 'launch', 'marina', 'mariner', 'mast',
    'navigator', 'ocean', 'pier', 'pilot', 'port', 'quest', 'raft', 'reef',
    'rudder', 'sailor', 'schooner', 'sea', 'ship', 'shore', 'tide', 'voyage',
    'whale', 'yacht'
  ];

  static String generate() {
    final adj = _adjectives[_random.nextInt(_adjectives.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    final number = _random.nextInt(9000) + 1000;
    return '$adj$noun$number';
  }
}
