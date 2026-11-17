import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/resources/studio_shader_compiler.dart';
import 'package:theme_studio/src/inspector/studio_shader_playground.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real compiler reflects vector slots in declaration order and reports errors', () async {
    final tool = StudioShaderCompiler(directory: Directory.current);
    final compiled = await tool.compile(studioShaderExample);
    expect(compiled.bytes.length, greaterThan(100));
    expect(compiled.uniformNames, [
      'resolution.x',
      'resolution.y',
      'time',
      'color.x',
      'color.y',
      'color.z',
    ]);
    expect(compiled.textureNames, isEmpty);
    expect(
      getDefaultShaderUniform('resolution.x').source,
      SceneUniformSource.width,
    );
    expect(getDefaultShaderUniform('time').source, SceneUniformSource.time);
    await expectLater(
      tool.compile(
        studioShaderExample.replaceFirst('void main()', 'void broken('),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toLowerCase(),
          'diagnostic',
          contains('error'),
        ),
      ),
    );
    expect(
      (await tool.compile(studioShaderExample)).uniformNames,
      compiled.uniformNames,
    );
  });
  test(
    'samplers have a separate ordered texture table and include paths resolve',
    () async {
      final temp = await Directory.systemTemp.createTemp('studio-shader-test-');
      addTearDown(() => temp.delete(recursive: true));
      await File('${temp.path}/color.glsl')
          .writeAsString('vec4 tint(vec4 color) { return color; }');
      final tool = StudioShaderCompiler(directory: temp);
      final compiled = await tool.compile(
        '''#include <flutter/runtime_effect.glsl>
#include "color.glsl"
uniform vec2 uSize;
uniform sampler2D image;
uniform float uTime;
out vec4 fragColor;
void main(){fragColor=tint(texture(image,FlutterFragCoord().xy/uSize))*(0.5+0.5*sin(uTime));}
''',
      );
      expect(compiled.uniformNames, ['uSize.x', 'uSize.y', 'uTime']);
      expect(compiled.textureNames, ['image']);
    },
  );

  test('compile rejects escaping includeDirectory and #include paths', () async {
    final root = await Directory.systemTemp.createTemp('studio-shader-confine-');
    addTearDown(() => root.delete(recursive: true));
    final theme = Directory('${root.path}/theme')..createSync();
    final outside = Directory('${root.path}/outside')..createSync();
    await File('${outside.path}/secret.glsl')
        .writeAsString('vec4 secret() { return vec4(1.0); }');
    await Link('${theme.path}/link.glsl').create('${outside.path}/secret.glsl');

    await File('${theme.path}/nested.glsl')
        .writeAsString('#include <../outside/secret.glsl>');

    final tool = StudioShaderCompiler(directory: theme);

    await expectLater(
      tool.compile(studioShaderExample, includeDirectory: outside),
      throwsFormatException,
    );
    for (final directive in const [
      '#include "../outside/secret.glsl"',
      '#include <../outside/secret.glsl>',
      '#include "/etc/passwd"',
      r'#include "..\outside\secret.glsl"',
      '#include "link.glsl"',
      '#include <link.glsl>',
      '#include "nested.glsl"',
    ]) {
      await expectLater(
        tool.compile('#include <flutter/runtime_effect.glsl>\n$directive\n$studioShaderExample'),
        throwsFormatException,
      );
    }
  });

  test('loadCompiled cleans stale shader cache and loadFile coalesces concurrent calls', () async {
    final root = await Directory.systemTemp.createTemp('studio-shader-cache-');
    addTearDown(() => root.delete(recursive: true));
    final theme = Directory('${root.path}/theme')..createSync();
    final assetDir = Directory('${root.path}/flutter_assets')..createSync();
    final staleDir = Directory('${assetDir.path}/.akari-studio-shaders')
      ..createSync();
    final staleFile = File('${staleDir.path}/stale.frag')..writeAsBytesSync([0]);

    var compileRuns = 0;
    final compilerTool = _CountingShaderCompiler(
      directory: theme,
      assetDirectory: assetDir,
      onCompile: () => compileRuns++,
    );
    final shaderFile = File('${theme.path}/assets/bg.frag')
      ..createSync(recursive: true)
      ..writeAsStringSync(studioShaderExample);

    // Concurrent calls on identical source should share one compilation, even if
    // Flutter test asset loading subsequently fails (leaving no cache leak).
    await expectLater(
      Future.wait([
        compilerTool.loadFile('assets/bg.frag', shaderFile),
        compilerTool.loadFile('assets/bg.frag', shaderFile),
      ]),
      throwsA(anything),
    );
    expect(compileRuns, 1);
    expect(staleFile.existsSync(), isFalse);
    expect(staleDir.existsSync(), isFalse);
  });
}

class _CountingShaderCompiler extends StudioShaderCompiler {
  _CountingShaderCompiler({
    required super.directory,
    super.assetDirectory,
    required this.onCompile,
  });

  final VoidCallback onCompile;

  @override
  Future<StudioCompiledShader> compile(
    String source, {
    Directory? includeDirectory,
  }) {
    onCompile();
    return super.compile(source, includeDirectory: includeDirectory);
  }
}
