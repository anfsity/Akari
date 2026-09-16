import 'dart:async';

import 'package:dbus/dbus.dart';

import '../../feature/greeter/greeter_state.dart';
import '../../feature/greeter/ports/greeter_gateway.dart';

const _busName = 'io.mozais.Greeter';
const _objectPath = '/io/mozais/Greeter';
const _interfaceName = 'io.mozais.Greeter1';

/// D-Bus implementation of the Feature gateway.
///
/// This class owns transport values and signal subscriptions only. It maps
/// them into typed frontend events before they reach Feature.
class DBusGreeterGateway implements GreeterGateway {
  DBusGreeterGateway({DBusClient? client})
    : _client = client ?? DBusClient.session(),
      _events = StreamController<GreeterEvent>.broadcast() {
    _object = DBusRemoteObject(
      _client,
      name: _busName,
      path: DBusObjectPath(_objectPath),
    );
    _listenToSignals();
  }

  final DBusClient _client;
  final StreamController<GreeterEvent> _events;
  final List<StreamSubscription<DBusSignal>> _signalSubscriptions = [];
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
  Future<List<UserSummary>> listUsers() async {
    final response = await _call(
      'ListUsers',
      replySignature: DBusSignature('a(sss)'),
    );
    return response.returnValues.single.asArray().map((value) {
      final [id, displayName, ...] = value.asStruct();
      return UserSummary(
        id: id.asString(),
        displayName: displayName.asString(),
      );
    }).toList();
  }

  @override
  Future<List<SessionSummary>> listSessions() async {
    final response = await _call(
      'ListSessions',
      errorKind: GreeterErrorKind.session,
      replySignature: DBusSignature('a(ssas)'),
    );
    return response.returnValues.single.asArray().map((value) {
      final [id, name, ...] = value.asStruct();
      return SessionSummary(id: id.asString(), name: name.asString());
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
  Future<void> powerAction(PowerAction action) async {
    await _call(
      'PowerAction',
      errorKind: GreeterErrorKind.power,
      values: [DBusString(_getPowerActionName(action))],
    );
  }

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

  void _listenToSignals() {
    final promptStream = DBusRemoteObjectSignalStream(
      object: _object,
      interface: _interfaceName,
      name: 'Prompt',
      signature: DBusSignature('sss'),
    );
    final stateStream = DBusRemoteObjectSignalStream(
      object: _object,
      interface: _interfaceName,
      name: 'StateChanged',
      signature: DBusSignature('sss'),
    );

    _signalSubscriptions.add(
      promptStream.listen(
        _onPrompt,
        onError: _onTransportError,
        onDone: _onTransportDone,
      ),
    );
    _signalSubscriptions.add(
      stateStream.listen(
        _onStateChanged,
        onError: _onTransportError,
        onDone: _onTransportDone,
      ),
    );
  }

  void _onPrompt(DBusSignal signal) {
    try {
      final values = signal.values;
      _events.add(
        BackendPromptReceived(
          attemptId: values[0].asString(),
          kind: _getPromptKind(values[1].asString()),
          text: values[2].asString(),
        ),
      );
    } on Object {
      _events.add(const BackendDisconnected());
    }
  }

  void _onStateChanged(DBusSignal signal) {
    try {
      final values = signal.values;
      _events.add(
        BackendStateChanged(
          attemptId: values[0].asString(),
          state: _getBackendAuthState(values[1].asString()),
          detail: values[2].asString(),
        ),
      );
    } on Object {
      _events.add(const BackendDisconnected());
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    if (!_closed) {
      _events.add(const BackendDisconnected());
    }
  }

  void _onTransportDone() {
    if (!_closed) {
      _events.add(const BackendDisconnected());
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

  String _getDisplayError(Object error) {
    if (error is DBusErrorException && error.message.isNotEmpty) {
      return error.message;
    }
    return 'The greeter service is unavailable.';
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _signalSubscriptions.clear();
    await _client.close();
    await _events.close();
  }
}
