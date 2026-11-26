import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preview_host.dart';

/// Material and localization belong to the compiled theme preview. Editor
/// controls keep using shadcn; design mode keeps authoring hit tests stable.
class PreviewScene extends StatelessWidget {
  const PreviewScene({
    required this.theme,
    required this.document,
    required this.referenceSize,
    required this.interactive,
    required this.wakeProgress,
    required this.activePredicates,
    required this.nodeBuilder,
    required this.frameBuilder,
    required this.playback,
    required this.contentDecorator,
    required this.assetImageResolver,
    required this.assetSvgLoader,
    required this.assetFontLoader,
    required this.shaderLoader,
    super.key,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final bool interactive;
  final Animation<double> wakeProgress;
  final Set<ScenePredicate> activePredicates;
  final SceneNodeBuilder nodeBuilder;
  final SceneFrameBuilder frameBuilder;
  final ScenePlayback? playback;
  final SceneFrameBuilder contentDecorator;
  final SceneImageProviderResolver? assetImageResolver;
  final SceneSvgLoader? assetSvgLoader;
  final SceneFontLoader? assetFontLoader;
  final SceneShaderLoader? shaderLoader;
  final Size referenceSize;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.materialTheme,
    home: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: referenceSize,
        disableAnimations:
            !interactive || MediaQuery.disableAnimationsOf(context),
      ),
      child: Scaffold(
        body: SceneRuntime(
          document: document,
          theme: theme.bundle,
          backgroundBlurSigma: getBackgroundBlurAnimation(
            document.background,
            wakeProgress,
          ),
          activePredicates: activePredicates,
          nodeBuilder: nodeBuilder,
          frameBuilder: frameBuilder,
          playback: playback,
          contentDecorator: contentDecorator,
          assetImageResolver: assetImageResolver,
          assetSvgLoader: assetSvgLoader,
          assetFontLoader: assetFontLoader,
          shaderLoader: shaderLoader,
        ),
      ),
    ),
  );
}

class PreviewNode extends StatelessWidget {
  const PreviewNode({
    required this.nodeId,
    required this.interactive,
    required this.onSelect,
    required this.onDoubleTap,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
    required this.child,
    super.key,
  });

  final String nodeId;
  final bool interactive;
  final VoidCallback onSelect;
  final VoidCallback onDoubleTap;
  final GestureDragStartCallback? onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final GestureDragEndCallback onStopDrag;
  final GestureDragCancelCallback onCancelDrag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: interactive
        ? null
        : (event) {
            if (event.buttons == kPrimaryMouseButton) onSelect();
          },
    // Flutter reports an accepted pan's pointer cancellation as onPanEnd.
    // Clear the draft first so a cancelled pointer cannot commit a move.
    onPointerCancel: interactive ? null : (_) => onCancelDrag(),
    child: GestureDetector(
      key: ValueKey('preview-$nodeId'),
      behavior: HitTestBehavior.opaque,
      // Consume single taps immediately selected by the pointer listener so
      // double-click recognition cannot pass them to the blank-canvas tool.
      onTap: interactive ? null : () {},
      onDoubleTap: interactive ? null : onDoubleTap,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: onStartDrag,
      onPanUpdate: interactive ? null : onUpdateDrag,
      onPanEnd: interactive ? null : onStopDrag,
      onPanCancel: interactive ? null : onCancelDrag,
      child: ExcludeFocus(
        excluding: !interactive,
        child: IgnorePointer(ignoring: !interactive, child: child),
      ),
    ),
  );
}

class PreviewInteractiveFrame extends StatelessWidget {
  const PreviewInteractiveFrame({
    required this.nodeId,
    required this.readOnly,
    required this.interactive,
    required this.onSelect,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
    required this.child,
    super.key,
  });

  final String nodeId;
  final bool readOnly;
  final bool interactive;
  final VoidCallback onSelect;
  final GestureDragStartCallback onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final VoidCallback onStopDrag;
  final VoidCallback onCancelDrag;
  final Widget child;

  @override
  Widget build(BuildContext context) => interactive
      ? child
      : Listener(
          behavior: HitTestBehavior.translucent,
          onPointerCancel: (_) => onCancelDrag(),
          child: GestureDetector(
            key: ValueKey('preview-$nodeId'),
            behavior: HitTestBehavior.translucent,
            onTap: onSelect,
            onPanStart: readOnly ? null : onStartDrag,
            onPanUpdate: readOnly ? null : onUpdateDrag,
            onPanEnd: readOnly ? null : (_) => onStopDrag(),
            onPanCancel: onCancelDrag,
            child: child,
          ),
        );
}

Set<ScenePredicate> getPreviewPredicates(
  StudioPreviewHost simulation,
  bool dormant,
) => getActiveScenePredicates(
  service: simulation.host.serviceSlots.value,
  auth: simulation.host.authPromptSlots.value,
  account: simulation.host.accountPickerSlots.value,
  session: simulation.host.sessionPickerSlots.value,
  power: simulation.host.powerSlots.value,
  dormant: dormant,
);
