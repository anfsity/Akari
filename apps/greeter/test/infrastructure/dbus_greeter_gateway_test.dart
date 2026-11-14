import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter/infrastructure/dbus/greeter_dbus_gateway.dart';
import 'package:greeter_ui/greeter_ui.dart';

void main() {
  test(
    'emits BackendDisconnected on nameOwnerChanged loss and reconnects on getState',
    () async {
      final clients = <_FakeDBusClient>[];
      final signals = <StreamController<DBusSignal>>[];
      final gateway = DBusGreeterGateway(
        clientFactory: () {
          final client = _FakeDBusClient();
          clients.add(client);
          return client;
        },
        signalStreamFactory: (client) {
          final controller = StreamController<DBusSignal>.broadcast();
          signals.add(controller);
          return controller.stream;
        },
      );
      addTearDown(gateway.close);

      final events = <GreeterEvent>[];
      final sub = gateway.events.listen(events.add);
      addTearDown(sub.cancel);

      expect(clients, hasLength(1));
      clients.first.emitNameOwnerChanged(
        const DBusNameOwnerChangedEvent(
          'io.akari.Greeter',
          oldOwner: ':1.10',
          newOwner: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [isA<BackendDisconnected>()]);

      // Subsequent getState reconnects cleanly with a fresh DBusClient.
      final snapshot = await gateway.getState();
      expect(snapshot.state, BackendAuthState.idle);
      expect(clients, hasLength(2));
      expect(clients.first.closed, isTrue);

      for (final controller in signals) {
        await controller.close();
      }
    },
  );

  test(
    'classifies transport errors vs stale backend cancel errors accurately',
    () async {
      final clients = <_FakeDBusClient>[];
      final signals = StreamController<DBusSignal>.broadcast();
      addTearDown(signals.close);
      final gateway = DBusGreeterGateway(
        clientFactory: () {
          final client = _FakeDBusClient();
          clients.add(client);
          return client;
        },
        signalStreamFactory: (_) => signals.stream,
      );
      addTearDown(gateway.close);

      final events = <GreeterEvent>[];
      final sub = gateway.events.listen(events.add);
      addTearDown(sub.cancel);

      // Non-transport D-Bus failure on cancel keeps errorKind authentication
      // and does not emit BackendDisconnected.
      clients.first.nextError = DBusFailedException(
        DBusMethodErrorResponse.failed('stale or unknown attempt id'),
      );
      await expectLater(
        gateway.cancel('attempt-1'),
        throwsA(
          isA<GreeterGatewayException>()
              .having((e) => e.kind, 'kind', GreeterErrorKind.authentication)
              .having((e) => e.message, 'message', 'stale or unknown attempt id'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      // D-Bus ServiceUnknown is reclassified as transport and triggers disconnect.
      clients.first.nextError = DBusServiceUnknownException(
        DBusMethodErrorResponse(
          'org.freedesktop.DBus.Error.ServiceUnknown',
          [const DBusString('The name was not provided')],
        ),
      );
      await expectLater(
        gateway.beginAuthentication('alice'),
        throwsA(
          isA<GreeterGatewayException>()
              .having((e) => e.kind, 'kind', GreeterErrorKind.transport)
              .having((e) => e.message, 'message', serviceUnavailableMessage),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [isA<BackendDisconnected>()]);
    },
  );
}

class _FakeDBusClient extends Fake implements DBusClient {
  final _nameOwnerChanged =
      StreamController<DBusNameOwnerChangedEvent>.broadcast();
  bool closed = false;
  Object? nextError;

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged =>
      _nameOwnerChanged.stream;

  void emitNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    _nameOwnerChanged.add(event);
  }

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return DBusMethodSuccessResponse([
      const DBusString('Idle'),
      const DBusString(''),
    ]);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _nameOwnerChanged.close();
  }
}
