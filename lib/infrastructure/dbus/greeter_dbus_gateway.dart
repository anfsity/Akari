import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:greeter_ui/greeter_ui.dart';

const _busName = 'io.akari.Greeter';
const _objectPath = '/io/akari/Greeter';
const _interfaceName = 'io.akari.Greeter1';

/// D-Bus implementation of the Feature gateway.
///
/// This class owns transport values and signal subscriptions only. It maps
/// them into typed frontend events before they reach Feature.
class DBusGreeterGateway implements GreeterGateway {
  DBusGreeterGateway()
    : _client = DBusClient.session(),
      _events = StreamController<GreeterEvent>.broadcast() {
    _object = DBusRemoteObject(
      _client,
      name: _busName,
      path: DBusObjectPath(_objectPath),
    );
    // One stream keeps Prompt and StateChanged in the order the backend emitted
    // them. Per-signal streams can interleave, letting a stale PromptPending
    // arrive after the Prompt and reset the credential field to a waiting state.
    _signalSubscription =
        DBusSignalStream(
          _client,
          sender: _busName,
          path: DBusObjectPath(_objectPath),
          interface: _interfaceName,
          signature: DBusSignature('sss'),
        ).listen(
          _onSignal,
          onError: (Object error, StackTrace stackTrace) =>
              _handleDisconnection(),
          onDone: _handleDisconnection,
        );
  }

  final DBusClient _client;
  final StreamController<GreeterEvent> _events;
  late final StreamSubscription<DBusSignal> _signalSubscription;
  late final DBusRemoteObject _object;
  bool _closed = false;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async {
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
    );
  }

  @override
  Future<void> cancel(String attemptId) async {
    await _call(
      'Cancel',
      errorKind: GreeterErrorKind.authentication,
      values: [DBusString(attemptId)],
    );
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    await _call(
      'StartSession',
      errorKind: GreeterErrorKind.session,
      values: [DBusString(attemptId), DBusString(sessionId)],
    );
  }

  @override
  Future<void> requestPowerAction(PowerAction action) async {
    await _call(
      'PowerAction',
      errorKind: GreeterErrorKind.power,
      values: [DBusString(_getPowerActionName(action))],
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
    try {
      return await _object.callMethod(
        _interfaceName,
        method,
        values,
        replySignature: replySignature,
      );
    } on Object catch (error) {
      throw GreeterGatewayException(_getDisplayError(error), kind: errorKind);
    }
  }

  void _onSignal(DBusSignal signal) {
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
      _events.add(const BackendDisconnected());
    }
  }

  void _handleDisconnection() {
    if (!_closed) _events.add(const BackendDisconnected());
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
    await _signalSubscription.cancel();
    await _client.close();
    await _events.close();
  }
}
