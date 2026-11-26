import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:theme_sdk/theme_sdk.dart';

import 'confined_path.dart';

class StudioCompiledShader {
  const StudioCompiledShader({
    required this.source,
    required this.bytes,
    required this.uniformNames,
    required this.textureNames,
  });
  final String source;
  final Uint8List bytes;
  final List<String> uniformNames;
  final List<String> textureNames;
}

/// Uses the installed SDK's actual compiler and reflection. Failed compiles
/// never enter the program cache or replace a scene/source asset.
class StudioShaderCompiler {
  StudioShaderCompiler({
    required this.directory,
    this.compilerPath,
    this.assetDirectory,
  });
  final Directory directory;
  final String? compilerPath;
  final Directory? assetDirectory;
  final _programs =
      <String, ({String source, Future<ui.FragmentProgram> program})>{};
  final _dispatchLocks = <String, Future<void>>{};

  static final _includeDirectivePattern = RegExp(
    r'^\s*#\s*include\b(.*)$',
    multiLine: true,
  );
  static final _includeTargetPattern = RegExp(r'^(?:"([^"]*)"|<([^>]*)>)$');
  static const _compileTimeout = Duration(seconds: 30);
  static int _nextCacheId = 0;
  static final _activeTempLoadsByCache = <String, int>{};
  static final _cleanedCaches = <String>{};

  static String _normalizePreprocessorSource(String source) {
    final joined = source.replaceAll(RegExp(r'\\\r?\n'), '');
    final buffer = StringBuffer();
    var inString = false;
    var escaping = false;
    for (var i = 0; i < joined.length; i++) {
      final current = joined.codeUnitAt(i);
      final next = i + 1 < joined.length ? joined.codeUnitAt(i + 1) : -1;
      if (inString) {
        buffer.writeCharCode(current);
        if (current == 0x0A /* \n */ ) {
          inString = false;
          escaping = false;
        } else if (escaping) {
          escaping = false;
        } else if (current == 0x5C /* \ */ ) {
          escaping = true;
        } else if (current == 0x22 /* " */ ) {
          inString = false;
        }
        continue;
      }
      if (current == 0x22 /* " */ ) {
        inString = true;
        buffer.writeCharCode(current);
        continue;
      }
      if (current == 0x2F /* / */ && next == 0x2F /* / */ ) {
        i += 2;
        while (i < joined.length && joined.codeUnitAt(i) != 0x0A /* \n */ ) {
          i++;
        }
        if (i < joined.length) buffer.writeCharCode(0x0A);
        continue;
      }
      if (current == 0x2F /* / */ && next == 0x2A /* * */ ) {
        buffer.write(' ');
        i += 2;
        while (i + 1 < joined.length &&
            !(joined.codeUnitAt(i) == 0x2A /* * */ &&
                joined.codeUnitAt(i + 1) == 0x2F /* / */ )) {
          if (joined.codeUnitAt(i) == 0x0A /* \n */ ) {
            buffer.writeCharCode(0x0A);
          }
          i++;
        }
        if (i + 1 < joined.length) {
          i++;
        } else {
          i = joined.length;
        }
        continue;
      }
      buffer.writeCharCode(current);
    }
    return buffer.toString();
  }

  String _findCompiler() {
    if (compilerPath != null) return compilerPath!;
    final siblingCompiler = File(
      '${File(Platform.resolvedExecutable).parent.path}/impellerc',
    );
    if (siblingCompiler.existsSync()) return siblingCompiler.path;
    final roots = <Directory>[
      if (Platform.environment['FLUTTER_ROOT'] case final root?
          when root.isNotEmpty)
        Directory(root),
    ];
    var executableAncestor = File(Platform.resolvedExecutable).parent;
    for (var depth = 0; depth < 5; depth++) {
      if (File('${executableAncestor.path}/bin/flutter').existsSync()) {
        roots.add(executableAncestor);
        break;
      }
      final parent = executableAncestor.parent;
      if (parent.path == executableAncestor.path) break;
      executableAncestor = parent;
    }
    var ancestor = directory.absolute;
    while (true) {
      roots.add(Directory('${ancestor.path}/.fvm/flutter_sdk'));
      if (ancestor.parent.path == ancestor.path) break;
      ancestor = ancestor.parent;
    }
    for (final root in roots) {
      final file = File(
        '${root.path}/bin/cache/artifacts/engine/linux-${Platform.version.contains('arm64') ? 'arm64' : 'x64'}/impellerc',
      );
      if (file.existsSync()) return file.path;
    }
    throw const FileSystemException(
      'Flutter shader compiler not found. Open Studio from a Flutter workspace or set FLUTTER_ROOT.',
    );
  }

  Directory _resolveIncludeDirectory(Directory? includeDirectory) {
    if (includeDirectory == null) return directory;
    if (!directory.existsSync() || !includeDirectory.existsSync()) {
      throw const FormatException(
        'Shader include directory must stay inside the current theme.',
      );
    }
    final rootPath = directory.resolveSymbolicLinksSync();
    if (!isCanonicalPathWithin(
      rootPath,
      includeDirectory.resolveSymbolicLinksSync(),
    )) {
      throw const FormatException(
        'Shader include directory must stay inside the current theme.',
      );
    }
    return includeDirectory;
  }

  void _validateLocalIncludes(String source, Directory includeDir) {
    final checkSymlinks = directory.existsSync() && includeDir.existsSync();
    final rootPath = checkSymlinks ? directory.resolveSymbolicLinksSync() : '';
    final rootIncludePath = checkSymlinks
        ? includeDir.resolveSymbolicLinksSync()
        : '';
    final visited = <String>{};

    void validateSource(String content, String currentDirPath) {
      final normalized = _normalizePreprocessorSource(content);
      for (final match in _includeDirectivePattern.allMatches(normalized)) {
        final rawTarget = match.group(1)!.trim();
        final targetMatch = _includeTargetPattern.firstMatch(rawTarget);
        if (targetMatch == null) {
          throw FormatException(
            'Shader #include path must stay within the current theme: $rawTarget',
          );
        }
        final included = (targetMatch.group(1) ?? targetMatch.group(2))!;
        final segments = parseSafeRelativeSegments(included);
        if (segments == null) {
          throw FormatException(
            'Shader #include path must stay within the current theme: $included',
          );
        }
        if (!checkSymlinks) continue;
        final searchDirs = <String>{currentDirPath, rootIncludePath};
        for (final baseDir in searchDirs) {
          final resolved = _resolveConfinedInclude(
            rootPath,
            baseDir,
            segments,
            included,
          );
          if (resolved != null) {
            if (!FileSystemEntity.isFileSync(resolved)) {
              throw FormatException(
                'Shader #include path must stay within the current theme: $included',
              );
            }
            if (visited.add(resolved)) {
              validateSource(
                File(resolved).readAsStringSync(),
                File(resolved).parent.path,
              );
            }
            break;
          }
        }
      }
    }

    validateSource(source, rootIncludePath);
  }

  String? _resolveConfinedInclude(
    String rootPath,
    String baseDir,
    List<String> segments,
    String rawInclude,
  ) {
    var current = baseDir;
    for (var i = 0; i < segments.length; i++) {
      current = '$current${Platform.pathSeparator}${segments[i]}';
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return null;
      }
      try {
        final isLast = i == segments.length - 1;
        final resolved = !isLast && type == FileSystemEntityType.directory
            ? Directory(current).resolveSymbolicLinksSync()
            : File(current).resolveSymbolicLinksSync();
        if (!isCanonicalPathWithin(rootPath, resolved)) {
          throw FormatException(
            'Shader #include path must stay within the current theme: $rawInclude',
          );
        }
        current = resolved;
      } on FileSystemException {
        throw FormatException(
          'Shader #include path must stay within the current theme: $rawInclude',
        );
      }
    }
    return current;
  }

  Future<StudioCompiledShader> compile(
    String source, {
    Directory? includeDirectory,
  }) async {
    final resolvedIncludeDir = _resolveIncludeDirectory(includeDirectory);
    _validateLocalIncludes(source, resolvedIncludeDir);
    final compiler = File(_findCompiler());
    final staging = await Directory.systemTemp.createTemp('akari-shader-');
    try {
      final input = File('${staging.path}/playground.frag');
      await input.writeAsString(source);
      final output = '${staging.path}/shader.iplr';
      final reflection = '${staging.path}/reflection.json';
      final process = await Process.start(compiler.path, [
        '--sksl',
        '--runtime-stage-gles',
        '--runtime-stage-gles3',
        '--runtime-stage-vulkan',
        '--iplr',
        '--sl=$output',
        '--spirv=$output.spirv',
        '--reflection-json=$reflection',
        '--input=${input.path}',
        '--input-type=frag',
        '--include=${resolvedIncludeDir.path}',
        '--include=${compiler.parent.path}/shader_lib',
        '--verbose',
      ]);
      final stdoutFuture = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(_compileTimeout);
      } on TimeoutException {
        process.kill();
        await Future.wait<Object?>([
          process.exitCode.catchError((_) => -1),
          stdoutFuture.catchError((_) => ''),
          stderrFuture.catchError((_) => ''),
        ]);
        throw const FormatException('Shader compilation timed out.');
      }
      final stdoutText = await stdoutFuture;
      final stderrText = await stderrFuture;
      if (exitCode != 0) {
        throw FormatException('$stderrText\n$stdoutText'.trim());
      }
      final data = jsonDecode(
        await File(reflection).readAsString(),
      ) as Map<String, dynamic>;
      final uniforms = List<Map<String, dynamic>>.from(
        data['uniforms'] as List,
      )..sort((a, b) => (a['location'] as int).compareTo(b['location'] as int));
      final names = <String>[];
      for (final uniform in uniforms) {
        final type = uniform['type'] as Map;
        final components = type['vec_size'] as int;
        if (type['type_name'] != 'ShaderType::kFloat' ||
            type['columns'] != 1 ||
            components < 1 ||
            components > 4 ||
            (type['array_elements'] != null && type['array_elements'] != 0)) {
          throw FormatException(
            'Unsupported Flutter uniform ${uniform['name']}: use float or vec2/vec3/vec4.',
          );
        }
        for (var i = 0; i < components; i++) {
          names.add(
            '${uniform['name']}${components == 1 ? '' : '.${'xyzw'[i]}'}',
          );
        }
      }
      final textures = List<Map<String, dynamic>>.from(
        data['sampled_images'] as List,
      )..sort((a, b) => (a['location'] as int).compareTo(b['location'] as int));
      return StudioCompiledShader(
        source: source,
        bytes: await File(output).readAsBytes(),
        uniformNames: names,
        textureNames: [
          for (final texture in textures) texture['name'] as String,
        ],
      );
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<ui.FragmentProgram> loadCompiled(StudioCompiledShader compiled) async {
    final root =
        assetDirectory ??
        Directory(
          '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets',
        );
    if (!root.existsSync()) {
      throw const FileSystemException(
        'A desktop Studio bundle is required for live shader previews.',
      );
    }
    final cache = Directory('${root.path}/.akari-studio-shaders');
    final cacheKey = cache.path;
    final activeLoads = _activeTempLoadsByCache[cacheKey] ?? 0;
    if (activeLoads == 0 && _cleanedCaches.add(cacheKey)) {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    }
    _activeTempLoadsByCache[cacheKey] = activeLoads + 1;
    final file = File(
      '$cacheKey/shader-${DateTime.now().microsecondsSinceEpoch}-${_nextCacheId++}.frag',
    );
    try {
      await cache.create(recursive: true);
      await file.writeAsBytes(compiled.bytes);
      return await ui.FragmentProgram.fromAsset(
        '.akari-studio-shaders/${file.uri.pathSegments.last}',
      );
    } finally {
      if (await file.exists()) await file.delete();
      final remaining = (_activeTempLoadsByCache[cacheKey] ?? 1) - 1;
      if (remaining <= 0) {
        _activeTempLoadsByCache.remove(cacheKey);
        if (await cache.exists()) {
          try {
            await cache.delete(recursive: true);
          } on FileSystemException {
            // Another process or handle may hold the directory briefly.
          }
        }
      } else {
        _activeTempLoadsByCache[cacheKey] = remaining;
      }
    }
  }

  void retainProgram(
    String asset,
    StudioCompiledShader compiled,
    ui.FragmentProgram program,
  ) {
    _programs[asset] = (
      source: compiled.source,
      program: Future.value(program),
    );
  }

  Future<T> _synchronized<T>(String asset, Future<T> Function() action) {
    final previous = _dispatchLocks[asset] ?? Future<void>.value();
    final current = previous.then((_) => action(), onError: (_) => action());
    late final Future<void> sentinel;
    sentinel = current.then((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_dispatchLocks[asset], sentinel)) {
        _dispatchLocks.remove(asset);
      }
    });
    _dispatchLocks[asset] = sentinel;
    return current;
  }

  Future<ui.FragmentProgram> loadFile(String asset, File file) async {
    final pending = await _synchronized(asset, () async {
      final source = await file.readAsString();
      final cached = _programs[asset];
      if (cached != null && cached.source == source) {
        return (program: cached.program);
      }
      late final Future<ui.FragmentProgram> future;
      future = _compileAndLoadFile(file, source, () {
        if (identical(_programs[asset]?.program, future)) {
          _programs.remove(asset);
        }
      });
      _programs[asset] = (source: source, program: future);
      return (program: future);
    });
    return await pending.program;
  }

  Future<ui.FragmentProgram> _compileAndLoadFile(
    File file,
    String source,
    void Function() evictIfCurrent,
  ) async {
    try {
      final compiled = await compile(source, includeDirectory: file.parent);
      return await loadCompiled(compiled);
    } on Object {
      evictIfCurrent();
      rethrow;
    }
  }
}

SceneShaderUniform getDefaultShaderUniform(String name) {
  final lower = name.toLowerCase();
  final source = lower == 'time' || lower == 'utime' || lower == 'itime'
      ? SceneUniformSource.time
      : (lower.contains('resolution') || lower.contains('size')) &&
            lower.endsWith('.x')
      ? SceneUniformSource.width
      : (lower.contains('resolution') || lower.contains('size')) &&
            lower.endsWith('.y')
      ? SceneUniformSource.height
      : (lower.contains('mouse') || lower.contains('pointer')) &&
            lower.endsWith('.x')
      ? SceneUniformSource.pointerX
      : (lower.contains('mouse') || lower.contains('pointer')) &&
            lower.endsWith('.y')
      ? SceneUniformSource.pointerY
      : SceneUniformSource.constant;
  return SceneShaderUniform(
    name: name,
    source: source,
    value: source == SceneUniformSource.constant && lower.contains('color')
        ? 1
        : 0,
  );
}
