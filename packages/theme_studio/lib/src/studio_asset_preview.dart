import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_assets.dart';

class StudioAssetSurface extends StatelessWidget {
  const StudioAssetSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: CustomPaint(painter: const _TransparencyPainter(), child: child),
  );
}

class _TransparencyPainter extends CustomPainter {
  const _TransparencyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0.0; y < size.height; y += 10) {
      for (var x = 0.0; x < size.width; x += 10) {
        paint.color = (x ~/ 10 + y ~/ 10).isEven
            ? const Color(0xffc4c4c4)
            : const Color(0xffe0e0e0);
        canvas.drawRect(Rect.fromLTWH(x, y, 10, 10), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TransparencyPainter oldDelegate) => false;
}

class StudioAssetPreview extends StatefulWidget {
  const StudioAssetPreview({
    required this.path,
    required this.resolveImage,
    required this.loadText,
    required this.loadFont,
    this.tint,
    this.expanded = false,
    this.initialSample,
    super.key,
  });
  final String path;
  final ImageProvider Function(String) resolveImage;
  final SceneSvgLoader loadText;
  final Future<String> Function(String) loadFont;
  final int? tint;
  final bool expanded;
  final String? initialSample;
  @override
  State<StudioAssetPreview> createState() => _StudioAssetPreviewState();
}

class _StudioAssetPreviewState extends State<StudioAssetPreview> {
  late final _sample = TextEditingController(
    text: widget.initialSample ?? 'Aa · Welcome · 欢迎 · 0123456789',
  );
  late double _fontSize = widget.expanded ? 48 : 22;
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
  void reassemble() {
    super.reassemble();
    _loadContent();
  }

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  void _openFontPreview() {
    showOverlay<void>(
      context,
      const DialogConfiguration(),
      builder: (context) => AlertDialog(
        title: Text(widget.path.split('/').last),
        content: SizedBox(
          width: 560,
          height: 320,
          child: StudioAssetPreview(
            path: widget.path,
            resolveImage: widget.resolveImage,
            loadText: widget.loadText,
            loadFont: widget.loadFont,
            expanded: true,
            initialSample: _sample.text,
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      switch (getStudioAssetKind(widget.path)) {
        StudioAssetKind.image ||
        StudioAssetKind.material ||
        StudioAssetKind.svg => StudioAssetSurface(
          child: SizedBox(
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
        ),
        StudioAssetKind.font => FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.expanded)
                Row(
                  children: [
                    const Expanded(child: Text('Font sample')),
                    GhostButton(
                      key: const ValueKey('expand-font-preview'),
                      onPressed: _openFontPreview,
                      child: const Icon(LucideIcons.expand, size: 16),
                    ),
                  ],
                ),
              TextField(
                key: const ValueKey('font-preview-text'),
                controller: _sample,
                onChanged: (_) => setState(() {}),
              ),
              const Gap(8),
              if (snapshot.hasData)
                SizedBox(
                  height: widget.expanded ? 160 : 32,
                  child: SingleChildScrollView(
                    child: Text(
                      _sample.text,
                      key: const ValueKey('font-preview-sample'),
                      maxLines: widget.expanded ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: snapshot.data,
                        fontSize: _fontSize,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  snapshot.hasError
                      ? 'Unable to preview this font.'
                      : 'Loading font…',
                ).small().muted(),
              if (widget.expanded) ...[
                const Gap(20),
                Text('Size · ${_fontSize.round()} px').small().muted(),
                Slider(
                  value: SliderValue.single(_fontSize),
                  min: 12,
                  max: 96,
                  onChanged: (value) => setState(() => _fontSize = value.value),
                ),
              ],
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
