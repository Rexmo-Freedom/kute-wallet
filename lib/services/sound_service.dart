import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static AudioPlayer? _player;

  static AudioPlayer get _instance => _player ??= AudioPlayer();

  /// Play when a payment is sent (Bitcoin, Spark, Lightning).
  static Future<void> playSend() async {
    try {
      await _instance.play(AssetSource('lib/assets/sounds/send.wav'));
    } catch (_) {}
  }

  /// Play on successful deposit, bet placement, or swap.
  static Future<void> playSuccess() async {
    try {
      await _instance.play(AssetSource('lib/assets/sounds/success.wav'));
    } catch (_) {}
  }
}
