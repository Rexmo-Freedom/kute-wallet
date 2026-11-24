import 'package:flutter/services.dart' show MethodChannel;
import 'package:kute/services/onchain/native_onchain_service.dart'
    show OnchainTransport;

/// iOS and Android: native BDK behind the channel.
OnchainTransport platformOnchainTransport(MethodChannel channel) =>
    (method, args) => channel.invokeMethod<Object?>(method, args);
