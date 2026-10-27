import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_assets.dart';

class StudioAssetPreview extends StatefulWidget {
  const StudioAssetPreview({
    required this.path,
    required this.resolveImage,
    required this.loadText,
    required this.loadFont,
    this.tint,
    super.key,
  });
  final String path;
  final ImageProvider Function(String) resolveImage;
  final SceneSvgLoader loadText;
  final Future<String> Function(String) loadFont;
  final int? tint;
  @override
  State<StudioAssetPreview> createState() => _StudioAssetPreviewState();
}

class _StudioAssetPreviewState extends State<StudioAssetPreview> {
  final _sample = TextEditingController(text: 'Aa · Welcome · 欢迎 · 0123456789');
  Future<String>? _content;
  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void didUpdateWidget(StudioAssetPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.loadText != widget.loadText ||
        old.loadFont != widget.loadFont) {
      _loadContent();
    }
  }

  void _loadContent() {
    _content = switch (getStudioAssetKind(widget.path)) {
      StudioAssetKind.font => widget.loadFont(widget.path),
      StudioAssetKind.shader => widget.loadText(widget.path),
      _ => null,
    };
  }

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      switch (getStudioAssetKind(widget.path)) {
        StudioAssetKind.image ||
        StudioAssetKind.material ||
        StudioAssetKind.svg => SizedBox(
          height: 120,
          child: SceneAssetView(
            asset: SceneAsset(
              path: widget.path,
              kind: getStudioAssetKind(widget.path) == StudioAssetKind.svg
                  ? SceneAssetKind.svg
                  : SceneAssetKind.image,
              tint: widget.tint,
            ),
            resolveImage: widget.resolveImage,
            loadSvg: widget.loadText,
          ),
        ),
        StudioAssetKind.font => FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('font-preview-text'),
                controller: _sample,
                onChanged: (_) => setState(() {}),
              ),
              const Gap(8),
              if (snapshot.hasData)
                Text(
                  _sample.text,
                  key: const ValueKey('font-preview-sample'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: snapshot.data, fontSize: 28),
                )
              else
                Text(
                  snapshot.hasError
                      ? 'Unable to preview this font.'
                      : 'Loading font…',
                ).small().muted(),
            ],
          ),
        ),
        StudioAssetKind.shader => FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) => Text(
            snapshot.hasError
                ? 'Unable to read this shader.'
                : snapshot.data?.split('\n').take(10).join('\n') ??
                      'Loading shader…',
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        StudioAssetKind.audio => const Text('Audio asset').small().muted(),
        StudioAssetKind.other => const SizedBox.shrink(),
      };
}
