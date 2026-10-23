// Exercise the exact bridge/FFI dependencies resolved by the pinned SDK,
// without introducing a separate app-level dependency or version override.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:ffi';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
// The regression deliberately exercises the pinned bridge's real stream.
// ignore: implementation_imports
import 'package:flutter_rust_bridge/src/codec/base.dart';
// ignore: implementation_imports
import 'package:flutter_rust_bridge/src/ffigen_generated/multi_package.dart'
    show Dart_CObject, Dart_CObject_Type;
// ignore: implementation_imports
import 'package:flutter_rust_bridge/src/stream/stream_sink.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

class _CloseCodec extends BaseCodec<spark.SdkEvent, Object, Object> {
  const _CloseCodec();
  @override
  spark.SdkEvent decodeObject(dynamic raw) => throw CloseStreamException();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// No wallet/native SDK is opened. A Dart VM native-port message simulates
/// the StreamSink close sent when SDK disconnect drops its event listener.
class _NativeOwnedEvents {
  final sink = RustStreamSink<spark.SdkEvent>();
  late final int port =
      int.parse(sink.setupAndSerialize(codec: const _CloseCodec()));
  bool closed = false;
  Stream<spark.SdkEvent> get stream {
    port;
    return sink.stream;
  }

  void closeFromNative() {
    if (closed) return;
    closed = true;
    final message = calloc<Dart_CObject>();
    try {
      message.ref.typeAsInt = Dart_CObject_Type.Dart_CObject_kNull.value;
      final post = NativeApi.postCObject
          .cast<NativeFunction<Bool Function(Int64, Pointer<Dart_CObject>)>>()
          .asFunction<bool Function(int, Pointer<Dart_CObject>)>();
      expect(post(port, message), isTrue);
    } finally {
      calloc.free(message);
    }
  }
}

void _stub(_Sdk sdk, Stream<spark.SdkEvent> events) {
  when(() => sdk.addEventListener()).thenAnswer((_) => events);
  when(() => sdk.disconnect()).thenAnswer((_) async {});
  when(() =>
          sdk.getInfo(request: const spark.GetInfoRequest(ensureSynced: false)))
      .thenAnswer((_) async => spark.GetInfoResponse(
          identityPubkey: 'fixture',
          balanceSats: BigInt.one,
          tokenBalances: const {}));
  when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
      .thenAnswer((_) async => const spark.ListPaymentsResponse(payments: []));
}

void main() {
  for (final explicitDisconnect in [false, true]) {
    test(
        'live FRB cleanup starts native disconnect before awaiting stream cancellation; explicit=$explicitDisconnect',
        () async {
      final first = _Sdk(), second = _Sdk();
      final events = _NativeOwnedEvents();
      _stub(first, events.stream);
      _stub(second, const Stream.empty());
      final nativeStarted = Completer<void>();
      final nativeFinished = Completer<void>();
      when(() => first.disconnect()).thenAnswer((_) {
        if (!nativeStarted.isCompleted) nativeStarted.complete();
        events.closeFromNative();
        return nativeFinished.future;
      });
      var connects = 0;
      final wrapper = BreezSdkSpark.forTesting(
          connectSdk: (_) async => ++connects == 1 ? first : second);
      final request = _Request();
      await wrapper.connect(req: request);
      if (explicitDisconnect) wrapper.disconnect();
      final next = wrapper.connect(req: request);
      try {
        await pumpEventQueue();
        expect(nativeStarted.isCompleted, isTrue,
            reason:
                'FRB cancellation cannot finish until native disconnect drops the StreamSink');
        expect(connects, 1,
            reason:
                'stream closure alone cannot permit overlapping native handles');
        expect(wrapper.instance, isNull);
        nativeFinished.complete();
        await next.timeout(const Duration(seconds: 1));
        expect(wrapper.instance, same(second));
        expect(connects, 2);
      } finally {
        // Also cleanly release the deliberately deadlocked old implementation
        // when this regression is run red, without leaving a receive port open.
        events.closeFromNative();
        if (!nativeFinished.isCompleted) nativeFinished.complete();
        await next.catchError((Object _) {});
        wrapper.disconnect();
        await pumpEventQueue();
      }
    });
  }
}
