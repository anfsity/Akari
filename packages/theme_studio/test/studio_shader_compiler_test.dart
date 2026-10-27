import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/studio_shader_compiler.dart';
import 'package:theme_studio/src/studio_shader_playground.dart';

void main() {
  final compiler = File(
    '../../.fvm/flutter_sdk/bin/cache/artifacts/engine/linux-x64/impellerc',
  ).absolute;
  test('real compiler reflects vector slots in declaration order and reports errors', () async {
    final tool = StudioShaderCompiler(
      directory: Directory.current,
      compilerPath: compiler.path,
    );
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
      final tool = StudioShaderCompiler(
        directory: temp,
        compilerPath: compiler.path,
      );
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
}
