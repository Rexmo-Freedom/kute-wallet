import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kute/helpers/privacy_cover_bridge.dart';

/// Foreground feedback may continue through a biometric prompt Kute opened.
/// Other inactive states stop it. A real background visit must resume before
/// feedback can return, even if authentication persists across that visit.
abstract final class HapticLifecycle {
  static final _state = _HapticForeground();

  static ValueListenable<bool> get foreground => _state;
  static bool get isForeground => _state.value;
}

class _HapticForeground extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  _HapticForeground() : super(true) {
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _backgrounded = _isBackground(_lifecycle);
    WidgetsBinding.instance.addObserver(this);
    PrivacyCoverBridge.promptActive.addListener(_refresh);
    _refresh();
  }

  AppLifecycleState? _lifecycle;
  bool _backgrounded = false;

  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (_isBackground(state)) _backgrounded = true;
    if (state == AppLifecycleState.resumed) _backgrounded = false;
    _refresh();
  }

  void _refresh() {
    value = _lifecycle == null ||
        _lifecycle == AppLifecycleState.resumed ||
        (_lifecycle == AppLifecycleState.inactive &&
            !_backgrounded &&
            PrivacyCoverBridge.promptActive.value);
  }
}
