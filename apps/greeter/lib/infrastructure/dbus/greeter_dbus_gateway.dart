import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:greeter_ui/greeter_ui.dart';

const _busName = 'io.akari.Greeter';
const _objectPath = '/io/akari/Greeter';
const _interfaceName = 'io.akari.Greeter1';

typedef DBusClientFactory = DBusClient Function();
typedef DBusSignalStreamFactory = Stream<DBusSignal> Function(
  DBusClient client,
);

/// D-Bus implementation of the Feature gateway.
///
/// This class owns transport values and signal subscriptions only. It maps
/// them into typed frontend events before they reach Feature.
class DBusGreeterGateway implements GreeterGateway {
  DBusGreeterGateway({
    DBusClientFactory? clientFactory,
    @visibleForTesting DBusSignalStreamFactory? signalStreamFactory,
  }) : _clientFactory = clientFactory ?? DBusClient.session,
       _signalStreamFactory = signalStreamFactory ?? _createSignalStream,
       _events = StreamController<GreeterEvent>.broadcast() {
    _connection = _tryConnect();
  }

  final DBusClientFactory _clientFactory;
  final DBusSignalStreamFactory _signalStreamFactory;
  final StreamController<GreeterEvent> _events;
  _DBusConnection? _connection;
  Future<void>? _reconnecting;
  bool _closed = false;

  _DBusConnection? _tryConnect() {
    try {
      return _connect();
    } on Object {
      return null;
    }
  }

  static Stream<DBusSignal> _createSignalStream(DBusClient client) =>
      DBusSignalStream(
        client,
        sender: _busName,
        path: DBusObjectPath(_objectPath),
        interface: _interfaceName,
        signature: DBusSignature('sss'),
      );

  _DBusConnection _connect() {
    final client = _clientFactory();
    final object = DBusRemoteObject(
      client,
      name: _busName,
      path: DBusObjectPath(_objectPath),
    );
    late final _DBusConnection connection;
    // One stream keeps Prompt and StateChanged in the order the backend emitted
    // them. Per-signal streams can interleave, letting a stale PromptPending
    // arrive after the Prompt and reset the credential field to a waiting state.
    connection = _DBusConnection(
      client: client,
      object: object,
      signalSubscription: _signalStreamFactory(client).listen(
        (signal) => _onSignal(connection, signal),
        onError: (Object error, StackTrace stackTrace) =>
            _handleDisconnection(connection),
        onDone: () => _handleDisconnection(connection),
      ),
      nameOwnerSubscription: client.nameOwnerChanged.listen(
        (event) {
          if (event.name == _busName && (event.newOwner?.isEmpty ?? true)) {
            _handleDisconnection(connection);
          }
        },
        onError: (Object error, StackTrace stackTrace) =>
            _handleDisconnection(connection),
        onDone: () => _handleDisconnection(connection),
      ),
    );
    return connection;
  }

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async {
    if (!_closed && (_connection == null || _connection!.disconnected)) {
      await _reconnect();
    }
    final response = await _call(
      'GetState',
      replySignature: DBusSignature('ss'),
    );
    final [rawState, rawDetail] = response.returnValues;
    return BackendStateSnapshot(
      state: _getBackendAuthState(rawState.asString()),
      detail: rawDetail.asString(),
    );
  }

  @override
  Future<List<UserSummary>> getUsers() async {
    final response = await _call(
      'ListUsers',
      replySignature: DBusSignature('a(sss)'),
    );
    return response.returnValues.single.asArray().map((value) {
      final [id, displayName, iconPath] = value.asStruct();
      return UserSummary(
        id: id.asString(),
        displayName: displayName.asString(),
        iconPath: iconPath.asString(),
      );
    }).toList();
  }

  @override
  Future<List<SessionSummary>> getSessions() async {
    final response = await _call(
      'ListSessions',
      errorKind: GreeterErrorKind.session,
      replySignature: DBusSignature('a(ssas)'),
    );
    return response.returnValues.single.asArray().map((value) {
      // DesktopNames describe the backend's launch environment. The picker
      // needs only identity and label; it never constructs a session command.
      final [id, name, ...] = value.asStruct();
      return (id: id.asString(), name: name.asString());
    }).toList();
  }

  @override
  Future<String> beginAuthentication(String username) async {
    final response = await _call(
      'BeginAuthentication',
      errorKind: GreeterErrorKind.authentication,
      values: [DBusString(username)],
      replySignature: DBusSignature('s'),
    );
    return response.returnValues.single.asString();
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    await _call(
      'Respond',
      errorKind: GreeterErrorKind.authentication,
      values: [DBusString(attemptId), DBusString(response)],
      replySignature: DBusSignature(''),
    );
  }

  @override
  Future<void> cancel(String attemptId) async {
    await _call(
      'Cancel',
      errorKind: GreeterErrorKind.authentication,
      values: [DBusString(attemptId)],
      replySignature: DBusSignature(''),
    );
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    await _call(
      'StartSession',
      errorKind: GreeterErrorKind.session,
      values: [DBusString(attemptId), DBusString(sessionId)],
      replySignature: DBusSignature(''),
    );
  }

  @override
  Future<void> requestPowerAction(PowerAction action) async {
    await _call(
      'PowerAction',
      errorKind: GreeterErrorKind.power,
      values: [DBusString(_getPowerActionName(action))],
      replySignature: DBusSignature(''),
    );
  }

  // Reply signatures validate wire shape at this boundary. Normalize failures
  // here so feature recovery and theme notices never depend on D-Bus types.
  Future<DBusMethodSuccessResponse> _call(
    String method, {
    Iterable<DBusValue> values = const [],
    GreeterErrorKind errorKind = GreeterErrorKind.transport,
    DBusSignature? replySignature,
  }) async {
    final connection = _connection;
    if (_closed || connection == null) {
      throw const GreeterGatewayException(serviceUnavailableMessage);
    }
    try {
      return await connection.object.callMethod(
        _interfaceName,
        method,
        values,
        replySignature: replySignature,
      );
    } on Object catch (error) {
      if (_isTransportError(error)) {
        _handleDisconnection(connection);
        throw const GreeterGatewayException(serviceUnavailableMessage);
      }
      throw GreeterGatewayException(_getDisplayError(error), kind: errorKind);
    }
  }

  void _onSignal(_DBusConnection connection, DBusSignal signal) {
    if (_closed || !identical(connection, _connection) || _events.isClosed) {
      return;
    }
    try {
      switch (signal.name) {
        case 'Prompt':
          final [attemptId, kind, text] = signal.values;
          _events.add(
            BackendPromptReceived(
              attemptId: attemptId.asString(),
              kind: _getPromptKind(kind.asString()),
              text: text.asString(),
            ),
          );
        case 'StateChanged':
          final [attemptId, state, detail] = signal.values;
          _events.add(
            BackendStateChanged(
              attemptId: attemptId.asString(),
              state: _getBackendAuthState(state.asString()),
              detail: detail.asString(),
            ),
          );
      }
    } on Object {
      // Malformed protocol input leaves the conversation unusable. Report
      // loss of service rather than guessing how to answer a prompt.
      _handleDisconnection(connection);
    }
  }

  void _handleDisconnection(_DBusConnection connection) {
    if (_closed ||
        !identical(connection, _connection) ||
        connection.disconnected) {
      return;
    }
    connection.disconnected = true;
    if (!_events.isClosed) {
      _events.add(const BackendDisconnected());
    }
  }

  Future<void> _reconnect() => _reconnecting ??= () async {
    try {
      final previous = _connection;
      _connection = null;
      if (previous != null) {
        previous.disconnected = true;
        await _closeConnection(previous);
      }
      if (_closed) {
        return;
      }
      _connection = _tryConnect();
    } finally {
      _reconnecting = null;
    }
  }();

  Future<void> _closeConnection(_DBusConnection connection) async {
    await connection.signalSubscription.cancel();
    await connection.nameOwnerSubscription.cancel();
    try {
      await connection.client.close();
    } on Object {
      // Closing an already-broken socket is best-effort.
    }
  }

  PromptKind _getPromptKind(String value) {
    return switch (value) {
      'visible' => PromptKind.visible,
      'secret' => PromptKind.secret,
      'info' => PromptKind.info,
      'error' => PromptKind.error,
      _ => throw FormatException('unknown prompt kind'),
    };
  }

  BackendAuthState _getBackendAuthState(String value) {
    return switch (value) {
      'Idle' => BackendAuthState.idle,
      'CreatingSession' => BackendAuthState.creatingSession,
      'PromptPending' => BackendAuthState.promptPending,
      'WaitingForInput' => BackendAuthState.waitingForInput,
      'SubmittingResponse' => BackendAuthState.submittingResponse,
      'Authenticated' => BackendAuthState.authenticated,
      'ResolvingSession' => BackendAuthState.resolvingSession,
      'StartingSession' => BackendAuthState.startingSession,
      'HandingOff' => BackendAuthState.handingOff,
      'Cancelling' => BackendAuthState.cancelling,
      'Failed' => BackendAuthState.failed,
      _ => BackendAuthState.unknown,
    };
  }

  String _getPowerActionName(PowerAction action) {
    return switch (action) {
      PowerAction.powerOff => 'PowerOff',
      PowerAction.reboot => 'Reboot',
      PowerAction.suspend => 'Suspend',
      PowerAction.hibernate => 'Hibernate',
    };
  }

  bool _isTransportError(Object error) {
    if (error is! DBusErrorException) {
      return true;
    }
    if (error is DBusServiceUnknownException ||
        error is DBusUnknownObjectException ||
        error is DBusUnknownInterfaceException ||
        error is DBusUnknownMethodException ||
        error is DBusTimeoutException ||
        error is DBusTimedOutException) {
      return true;
    }
    return switch (error.response.errorName) {
      'org.freedesktop.DBus.Error.ServiceUnknown' ||
      'org.freedesktop.DBus.Error.NameHasNoOwner' ||
      'org.freedesktop.DBus.Error.NoReply' ||
      'org.freedesktop.DBus.Error.Timeout' ||
      'org.freedesktop.DBus.Error.TimedOut' ||
      'org.freedesktop.DBus.Error.Disconnected' => true,
      _ => false,
    };
  }

  String _getDisplayError(Object error) {
    // Backend method messages are display-safe under the Greeter1 contract.
    // Other exception strings may contain transport internals or payloads.
    if (error is DBusErrorException && error.message.isNotEmpty) {
      return error.message;
    }
    return serviceUnavailableMessage;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final connection = _connection;
    _connection = null;
    final reconnecting = _reconnecting;
    if (reconnecting != null) {
      await reconnecting;
    }
    if (connection != null) {
      await _closeConnection(connection);
    }
    await _events.close();
  }
}

class _DBusConnection {
  _DBusConnection({
    required this.client,
    required this.object,
    required this.signalSubscription,
    required this.nameOwnerSubscription,
  });

  final DBusClient client;
  final DBusRemoteObject object;
  final StreamSubscription<DBusSignal> signalSubscription;
  final StreamSubscription<DBusNameOwnerChangedEvent> nameOwnerSubscription;
  bool disconnected = false;
}
