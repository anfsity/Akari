import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:scene_schema/scene_schema.dart';

import 'background_renderer.dart';

typedef SceneSvgLoader = Future<String> Function(String asset);

/// Asset content is loaded once per source, independently of geometry and tint.
/// Studio can supply disk-backed loaders; production uses bundled resources.
class SceneAssetView extends StatefulWidget {
  const SceneAssetView({
    required this.asset,
    this.resolveImage,
    this.loadSvg,
    super.key,
  });
  final SceneAsset asset;
  final SceneImageProviderResolver? resolveImage;
  final SceneSvgLoader? loadSvg;
  @override
  State<SceneAssetView> createState() => _SceneAssetViewState();
}

class _SceneAssetViewState extends State<SceneAssetView> {
  Future<String>? _svg;
  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  @override
  void didUpdateWidget(SceneAssetView old) {
    super.didUpdateWidget(old);
    if (old.asset.path != widget.asset.path ||
        old.asset.kind != widget.asset.kind ||
        old.loadSvg != widget.loadSvg) {
      _loadSource();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _loadSource();
  }

  void _loadSource() {
    _svg = widget.asset.kind == SceneAssetKind.svg
        ? (widget.loadSvg?.call(widget.asset.path) ??
              rootBundle.loadString(widget.asset.path))
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final fit = switch (widget.asset.fit) {
      SceneAssetFit.contain => BoxFit.contain,
      SceneAssetFit.cover => BoxFit.cover,
      SceneAssetFit.fill => BoxFit.fill,
    };
    final tint = widget.asset.tint;
    if (widget.asset.kind == SceneAssetKind.image) {
      return Image(
        image:
            widget.resolveImage?.call(widget.asset.path) ??
            AssetImage(widget.asset.path),
        fit: fit,
        color: tint == null ? null : Color(tint),
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    }
    return FutureBuilder<String>(
      future: _svg,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Icon(Icons.broken_image_outlined);
        if (!snapshot.hasData) return const SizedBox.shrink();
        return SvgPicture.string(
          snapshot.data!,
          fit: fit,
          colorFilter: tint == null
              ? null
              : ColorFilter.mode(Color(tint), BlendMode.srcIn),
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
