import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/screens/receive/components/confirm_receive.dart';

/// Thin shell for the `/receive` route. Mirrors `pay/pay.dart` →
/// `ConfirmSend`: the actual UI lives in `ConfirmReceive`, which owns
/// its own AppBar + stepper. This file exists so `app_router.dart`
/// keeps its `/receive` → `Receive()` mapping unchanged.
///
/// This route is the BITCOIN receive. The Dollars tab has its own
/// screen (`screens/usd/usd_receive_screen.dart`).
class Receive extends ConsumerWidget {
  const Receive({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ConfirmReceive();
  }
}
