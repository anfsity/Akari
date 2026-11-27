import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:akari_cli/src/sdk_commands.dart';

const int _fnvOffsetBasis = (0xcbf29ce4 << 32) | 0x84222325;
const int _fnvPrime = 0x100000001b3;

Future<String> compileDartKernelSnapshot(
  Directory repoRoot, {
  required File source,
  required File output,
}) async {
  await output.parent.create(recursive: true);
  final dart = getDartCommand(repoRoot);
  final result = await Process.run(dart.first, [
    ...dart.skip(1),
    'compile',
    'kernel',
    '--packages=${Isolate.packageConfigSync!.toFilePath()}',
    '-o',
    output.path,
    source.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Failed to compile ${source.path} to ${output.path} '
      '(exit ${result.exitCode}):\n${result.stdout}\n${result.stderr}',
    );
  }
  return output.path;
}

Future<String> ensureAkariCliSnapshot(Directory repoRoot) async {
  final snapshotDirectory = Directory(
    '${repoRoot.path}/packages/akari_cli/.dart_tool/test_snapshots',
  );
  await snapshotDirectory.create(recursive: true);
  final digest = _computeAkariSourceFingerprint(repoRoot);
  final target = File('${snapshotDirectory.path}/akari-$digest.dill');
  if (target.existsSync()) {
    return target.path;
  }

  // `dart test` runs multiple test files as isolates inside one OS process, so
  // POSIX fcntl locks do not serialize them. Use atomic mkdir across both
  // isolates and processes, and publish the compiled snapshot via rename.
  final lockDirectory = Directory(
    '${snapshotDirectory.path}/akari-$digest.lock',
  );
  await _acquireDirectoryLock(lockDirectory);
  try {
    if (target.existsSync()) {
      return target.path;
    }
    final nonce =
        '${pid}_${identityHashCode(lockDirectory)}_${DateTime.now().microsecondsSinceEpoch}';
    final temp = File(
      '${snapshotDirectory.path}/akari-$digest.$nonce.tmp.dill',
    );
    try {
      await compileDartKernelSnapshot(
        repoRoot,
        source: File('${repoRoot.path}/packages/akari_cli/bin/akari.dart'),
        output: temp,
      );
      await temp.rename(target.path);
    } finally {
      if (temp.existsSync()) {
        await temp.delete();
      }
    }
    for (final entry in snapshotDirectory.listSync(followLinks: false)) {
      if (entry is File &&
          entry.path != target.path &&
          entry.uri.pathSegments.last.startsWith('akari-') &&
          entry.path.endsWith('.dill') &&
          !entry.path.endsWith('.tmp.dill')) {
        try {
          await entry.delete();
        } on PathNotFoundException {
          // Another isolate removed this stale snapshot concurrently.
        }
      }
    }
    return target.path;
  } finally {
    try {
      if (lockDirectory.existsSync()) {
        await lockDirectory.delete();
      }
    } on PathNotFoundException {
      // Already released.
    }
  }
}

Future<void> _acquireDirectoryLock(Directory lockDirectory) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (true) {
    try {
      lockDirectory.createSync();
      return;
    } on FileSystemException {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Timed out waiting for snapshot lock: ${lockDirectory.path}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

String _computeAkariSourceFingerprint(Directory repoRoot) {
  final files = <String, File>{};
  void addFile(File file) {
    if (!file.existsSync()) return;
    final relative = file.path.startsWith('${repoRoot.path}/')
        ? file.path.substring(repoRoot.path.length + 1)
        : file.path;
    files[relative] = file;
  }

  void addTree(Directory directory) {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        addFile(entity);
      }
    }
  }

  addFile(File('${repoRoot.path}/pubspec.lock'));
  for (final packageName in [
    'akari_cli',
    'theme_project',
    'scene_schema',
    'scene_codegen',
  ]) {
    final packageRoot = '${repoRoot.path}/packages/$packageName';
    addFile(File('$packageRoot/pubspec.yaml'));
    addTree(Directory('$packageRoot/bin'));
    addTree(Directory('$packageRoot/lib'));
  }

  var hash = _fnvOffsetBasis;
  void feedBytes(List<int> bytes) {
    for (final byte in bytes) {
      hash ^= byte;
      hash *= _fnvPrime;
    }
  }

  feedBytes(utf8.encode(Platform.version));
  feedBytes(const [0]);
  feedBytes(utf8.encode(getDartCommand(repoRoot).join(' ')));
  feedBytes(const [0]);
  final paths = files.keys.toList()..sort();
  for (final relative in paths) {
    feedBytes(utf8.encode(relative));
    feedBytes(const [0]);
    feedBytes(files[relative]!.readAsBytesSync());
    feedBytes(const [0]);
  }
  final high = (hash >>> 32).toRadixString(16).padLeft(8, '0');
  final low = (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
