import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greeter/infrastructure/preferences/file_session_store.dart';

void main() {
  late Directory directory;
  late FileSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('akari-session');
    store = FileSessionStore(file: File('${directory.path}/greeter.json'));
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('returns null when nothing was stored', () async {
    expect(await store.findSelectedSessionId(), isNull);
  });

  test('round-trips the selected session id', () async {
    await store.saveSelectedSessionId('wayland:hyprland');
    expect(await store.findSelectedSessionId(), 'wayland:hyprland');
  });

  test('returns null for malformed content', () async {
    await File('${directory.path}/greeter.json').writeAsString('not json');
    expect(await store.findSelectedSessionId(), isNull);
  });
}
