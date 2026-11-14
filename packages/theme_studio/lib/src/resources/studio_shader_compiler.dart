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

  static final _localIncludePattern = RegExp(
    r'^\s*#\s*include\s+"([^"]*)"',
    multiLine: true,
  );
  static int _nextCacheId = 0;
  static int _activeTempLoads = 0;
  static final _cleanedCaches = <String>{};

  String _findCompiler() {
    if (compilerPath != null) return compilerPath!;
    final roots = <Directory>[
      if (Platform.environment['FLUTTER_ROOT'] case final root?)
        Directory(root),
    ];
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
    final includePath = checkSymlinks
        ? includeDir.resolveSymbolicLinksSync()
        : '';
    for (final match in _localIncludePattern.allMatches(source)) {
      final included = match.group(1)!;
      final segments = parseSafeRelativeSegments(included);
      if (segments == null) {
        throw FormatException(
          'Shader #include path must stay within the current theme: $included',
        );
      }
      if (!checkSymlinks) continue;
      final candidate = '$includePath/${segments.join(Platform.pathSeparator)}';
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      try {
        final resolved = File(candidate).resolveSymbolicLinksSync();
        if (!isCanonicalPathWithin(rootPath, resolved)) {
          throw FormatException(
            'Shader #include path must stay within the current theme: $included',
          );
        }
      } on FileSystemException {
        throw FormatException(
          'Shader #include path must stay within the current theme: $included',
        );
      }
    }
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
      final result = await Process.run(compiler.path, [
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
      if (result.exitCode != 0) {
        throw FormatException('${result.stderr}\n${result.stdout}'.trim());
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
    if (_activeTempLoads == 0 && _cleanedCaches.add(cache.path)) {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    }
    _activeTempLoads++;
    final file = File(
      '${cache.path}/shader-${DateTime.now().microsecondsSinceEpoch}-${_nextCacheId++}.frag',
    );
    try {
      await cache.create(recursive: true);
      await file.writeAsBytes(compiled.bytes);
      return await ui.FragmentProgram.fromAsset(
        '.akari-studio-shaders/${file.uri.pathSegments.last}',
      );
    } finally {
      if (await file.exists()) await file.delete();
      _activeTempLoads--;
      if (_activeTempLoads == 0 && await cache.exists()) {
        try {
          await cache.delete(recursive: true);
        } on FileSystemException {
          // Another process or handle may hold the directory briefly.
        }
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
