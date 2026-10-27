import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scene_schema/scene_schema.dart';

import 'background_renderer.dart';

typedef SceneShaderLoader = Future<ui.FragmentProgram> Function(String asset);

/// Owns program instances, decoded texture handles and the animation clock.
/// Scrubbing supplies elapsed time; reduced motion uses a stable zero clock.
class SceneShaderBackground extends StatefulWidget {
  const SceneShaderBackground({
    required this.shader,
    this.loadProgram,
    this.resolveImage,
    this.elapsed,
    this.activePredicates = const {},
    this.predicatesListenable,
    this.onError,
    super.key,
  });
  final SceneShader shader;
  final SceneShaderLoader? loadProgram;
  final SceneImageProviderResolver? resolveImage;
  final Duration? elapsed;
  final Set<ScenePredicate> activePredicates;
  final ValueListenable<Set<ScenePredicate>>? predicatesListenable;
  final ValueChanged<String>? onError;
  @override
  State<SceneShaderBackground> createState() => _SceneShaderBackgroundState();
}

class _SceneShaderBackgroundState extends State<SceneShaderBackground>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  List<ui.Image> _textures = [];
  late final Ticker _clock = createTicker(
    (elapsed) => setState(() => _time = elapsed),
  );
  Duration _time = Duration.zero;
  Offset _pointer = Offset.zero;
  int _revision = 0;
  bool _reduced = false;
  bool _dependenciesReady = false;
  @override
  void initState() {
    super.initState();
    widget.predicatesListenable?.addListener(_refreshState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_dependenciesReady) {
      _dependenciesReady = true;
      unawaited(_load());
    }
    _updateClock();
  }

  @override
  void didUpdateWidget(SceneShaderBackground old) {
    super.didUpdateWidget(old);
    if (old.predicatesListenable != widget.predicatesListenable) {
      old.predicatesListenable?.removeListener(_refreshState);
      widget.predicatesListenable?.addListener(_refreshState);
    }
    if (old.shader.asset != widget.shader.asset ||
        old.loadProgram != widget.loadProgram ||
        old.resolveImage != widget.resolveImage ||
        !listEquals(
          old.shader.textures.map((texture) => texture.asset).toList(),
          widget.shader.textures.map((texture) => texture.asset).toList(),
        ) ||
        old.shader.uniforms.length != widget.shader.uniforms.length) {
      unawaited(_load());
    }
    _updateClock();
  }

  void _refreshState() => setState(() {});
  void _updateClock() {
    final running =
        widget.elapsed == null &&
        !_reduced &&
        widget.shader.uniforms.any(
          (uniform) => uniform.source == SceneUniformSource.time,
        );
    if (running && !_clock.isActive) {
      _clock.start();
    }
    if (!running && _clock.isActive) {
      _clock.stop();
    }
  }

  Future<ui.Image> _loadTexture(String asset) async {
    final image = (widget.resolveImage?.call(asset) ?? AssetImage(asset))
        .resolve(createLocalImageConfiguration(context));
    final completer = Completer<ui.Image>();
    final listener = ImageStreamListener(
      (info, _) => completer.complete(info.image.clone()),
      onError: (Object error, StackTrace? stack) =>
          completer.completeError(error, stack),
    );
    image.addListener(listener);
    try {
      return await completer.future;
    } finally {
      image.removeListener(listener);
    }
  }

  Future<void> _load() async {
    final revision = ++_revision;
    final definition = widget.shader;
    _shader?.dispose();
    _shader = null;
    for (final texture in _textures) {
      texture.dispose();
    }
    _textures = [];
    final textures = <ui.Image>[];
    ui.FragmentShader? shader;
    try {
      final program =
          await (widget.loadProgram ?? ui.FragmentProgram.fromAsset)(
            definition.asset,
          );
      shader = program.fragmentShader();
      for (final texture in definition.textures) {
        textures.add(await _loadTexture(texture.asset));
      }
      for (var i = 0; i < definition.uniforms.length; i++) {
        shader.setFloat(i, 0);
      }
      for (var i = 0; i < textures.length; i++) {
        shader.setImageSampler(i, textures[i]);
      }
      if (!mounted || revision != _revision) {
        shader.dispose();
        for (final texture in textures) {
          texture.dispose();
        }
        return;
      }
      setState(() {
        _shader?.dispose();
        for (final texture in _textures) {
          texture.dispose();
        }
        _shader = shader;
        _textures = textures;
      });
    } on Object catch (error) {
      shader?.dispose();
      for (final texture in textures) {
        texture.dispose();
      }
      if (mounted && revision == _revision) widget.onError?.call('$error');
    }
  }

  @override
  void dispose() {
    _revision++;
    widget.predicatesListenable?.removeListener(_refreshState);
    _clock.dispose();
    _shader?.dispose();
    for (final texture in _textures) {
      texture.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) return const SizedBox.expand();
    final predicates =
        widget.predicatesListenable?.value ?? widget.activePredicates;
    return MouseRegion(
      onHover: (event) => setState(() => _pointer = event.localPosition),
      child: CustomPaint(
        painter: _ShaderPainter(
          shader: _shader,
          definition: widget.shader,
          time: _reduced ? Duration.zero : widget.elapsed ?? _time,
          pointer: _pointer,
          predicates: predicates,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  const _ShaderPainter({
    required this.shader,
    required this.definition,
    required this.time,
    required this.pointer,
    required this.predicates,
  });
  final ui.FragmentShader? shader;
  final SceneShader definition;
  final Duration time;
  final Offset pointer;
  final Set<ScenePredicate> predicates;
  @override
  void paint(Canvas canvas, Size size) {
    final shader = this.shader;
    if (shader == null) return;
    for (var index = 0; index < definition.uniforms.length; index++) {
      final uniform = definition.uniforms[index];
      final value = switch (uniform.source) {
        SceneUniformSource.constant => 0.0,
        SceneUniformSource.time => time.inMicroseconds / 1000000,
        SceneUniformSource.width => size.width,
        SceneUniformSource.height => size.height,
        SceneUniformSource.pointerX => pointer.dx,
        SceneUniformSource.pointerY => pointer.dy,
        SceneUniformSource.dormant =>
          predicates.contains(ScenePredicate.isDormant) ? 1.0 : 0.0,
        SceneUniformSource.authError =>
          predicates.contains(ScenePredicate.isAuthError) ? 1.0 : 0.0,
      };
      shader.setFloat(index, value * uniform.scale + uniform.value);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
