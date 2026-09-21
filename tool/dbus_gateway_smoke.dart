import 'dart:async';
import 'dart:io';

import 'package:mozais_greeter_ui/feature/greeter/greeter_state.dart';
import 'package:mozais_greeter_ui/feature/greeter/ports/greeter_gateway.dart';
import 'package:mozais_greeter/infrastructure/dbus/greeter_dbus_gateway.dart';

Future<void> main() async {
  final gateway = DBusGreeterGateway();

  try {
    final state = await gateway.getState();
    final users = await gateway.listUsers();
    final sessions = await gateway.listSessions();
    final promptFuture = gateway.events
        .where(
          (event) =>
              event is BackendPromptReceived && event.kind == PromptKind.secret,
        )
        .cast<BackendPromptReceived>()
        .first;
    final attemptId = await gateway.beginAuthentication('alice');
    final prompt = await promptFuture.timeout(const Duration(seconds: 5));
    if (prompt.attemptId != attemptId) {
      throw StateError('prompt belongs to a different authentication attempt');
    }

    final idleFuture = gateway.events
        .where(
          (event) =>
              event is BackendStateChanged &&
              event.attemptId == attemptId &&
              event.state == BackendAuthState.idle,
        )
        .cast<BackendStateChanged>()
        .first;
    await gateway.cancel(attemptId);
    await idleFuture.timeout(const Duration(seconds: 5));
    stdout.writeln(
      'D-Bus gateway smoke passed: users=${users.length}, '
      'sessions=${sessions.length}, initial_state=${state.state.name}, '
      'prompt=true',
    );
  } finally {
    await gateway.close();
  }
}
