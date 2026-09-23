import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'condition_editor.dart';
import 'document_panel.dart';
import 'editor_controller.dart';
import 'editor_strings.dart';
import 'editor_widgets.dart';

/// Property panel for the document and the selected node.
///
/// The document-level canvas and background live in their own tab so the node
/// inspector is not a crowded wall of controls.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 6,
    vsync: this,
    animationDuration: Duration.zero,
  );
  final TabBarScrollController _tabScroll = TabBarScrollController();
  bool _middleDragActive = false;
  double _lastMiddleX = 0;

  @override
  void dispose() {
    _tabScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Column(
      children: [
        Listener(
          onPointerSignal: _handlePointerSignal,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: (_) => _middleDragActive = false,
          onPointerCancel: (_) => _middleDragActive = false,
          child: TabBar(
            controller: _tabs,
            scrollController: _tabScroll,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: strings.document),
              Tab(text: strings.identity),
              Tab(text: strings.layout),
              Tab(text: strings.transform),
              Tab(text: strings.visibility),
              Tab(text: strings.properties),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _tabs,
              widget.controller.documentListenable,
            ]),
            builder: (context, _) => _activeTab(),
          ),
        ),
      ],
    );
  }

  Widget _activeTab() {
    return switch (_tabs.index) {
      0 => DocumentPanel(controller: widget.controller),
      1 => _selectedNodeTab(
        (node) => _IdentityTab(controller: widget.controller, node: node),
      ),
      2 => _selectedNodeTab(
        (node) => _LayoutTab(controller: widget.controller, node: node),
      ),
      3 => _selectedNodeTab(
        (node) => _TransformTab(controller: widget.controller, node: node),
      ),
      4 => _selectedNodeTab(
        (node) => _VisibilityTab(controller: widget.controller, node: node),
      ),
      5 => _selectedNodeTab(
        (node) => _PropertiesTab(controller: widget.controller, node: node),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _selectedNodeTab(Widget Function(SceneNode node) builder) {
    return ListenableBuilder(
      listenable: widget.controller.selectionListenable,
      builder: (context, _) {
        final node = widget.controller.selectedNode;
        if (node == null) {
          return Center(
            child: Text(EditorStringsScope.of(context).selectANode),
          );
        }
        return builder(node);
      },
    );
  }

  /// Scrolls the tab strip with the wheel and with a middle-button drag.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _scrollTabsBy(event.scrollDelta.dy);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kMiddleMouseButton) {
      _middleDragActive = true;
      _lastMiddleX = event.position.dx;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_middleDragActive || event.buttons != kMiddleMouseButton) {
      return;
    }
    final delta = event.position.dx - _lastMiddleX;
    _lastMiddleX = event.position.dx;
    _scrollTabsBy(-delta);
  }

  void _scrollTabsBy(double delta) {
    if (!_tabScroll.hasClients) {
      return;
    }
    final position = _tabScroll.position;
    _tabScroll.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }
}

class _IdentityTab extends StatelessWidget {
  const _IdentityTab({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.identity,
          children: [
            _IdField(controller: controller, node: node),
            const SizedBox(height: 8),
            EnumDropdown<SceneNodeKind>(
              label: strings.kind,
              value: node.kind,
              values: SceneNodeKind.values,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(kind: value),
              ),
            ),
            const SizedBox(height: 8),
            NullableEnumDropdown<SceneAction>(
              label: strings.action,
              noneLabel: strings.none,
              value: node.action,
              values: SceneAction.values,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(action: value),
              ),
            ),
            const SizedBox(height: 8),
            EnumDropdown<SceneMotionPreset>(
              label: strings.motion,
              value: node.motion,
              values: SceneMotionPreset.values,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(motion: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LayoutTab extends StatelessWidget {
  const _LayoutTab({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    final canvas = controller.document!.canvas;

    void updatePixelRect({
      double? x,
      double? y,
      double? width,
      double? height,
    }) {
      controller.updateSelected((node) {
        final normalizedX = x == null
            ? node.rect.x
            : (x / canvas.referenceWidth)
                  .clamp(0.0, 1.0 - node.rect.width)
                  .toDouble();
        final normalizedY = y == null
            ? node.rect.y
            : (y / canvas.referenceHeight)
                  .clamp(0.0, 1.0 - node.rect.height)
                  .toDouble();
        final normalizedWidth = width == null
            ? node.rect.width
            : (width / canvas.referenceWidth)
                  .clamp(0.001, 1.0 - normalizedX)
                  .toDouble();
        final normalizedHeight = height == null
            ? node.rect.height
            : (height / canvas.referenceHeight)
                  .clamp(0.001, 1.0 - normalizedY)
                  .toDouble();
        return node.copyWith(
          rect: node.rect.copyWith(
            x: normalizedX,
            y: normalizedY,
            width: normalizedWidth,
            height: normalizedHeight,
          ),
        );
      });
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.rectNormalized,
          children: [
            LabeledSlider(
              label: strings.x,
              value: node.rect.x,
              min: 0,
              max: 1.0 - node.rect.width,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(rect: node.rect.copyWith(x: value)),
              ),
            ),
            LabeledSlider(
              label: strings.y,
              value: node.rect.y,
              min: 0,
              max: 1.0 - node.rect.height,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(rect: node.rect.copyWith(y: value)),
              ),
            ),
            LabeledSlider(
              label: strings.width,
              value: node.rect.width,
              min: node.rect.width < 0.01 ? node.rect.width : 0.01,
              max: 1.0 - node.rect.x,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(rect: node.rect.copyWith(width: value)),
              ),
            ),
            LabeledSlider(
              label: strings.height,
              value: node.rect.height,
              min: node.rect.height < 0.01 ? node.rect.height : 0.01,
              max: 1.0 - node.rect.y,
              onChanged: (value) => controller.updateSelected(
                (node) =>
                    node.copyWith(rect: node.rect.copyWith(height: value)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.rectPixels} (${canvas.referenceWidth} x '
              '${canvas.referenceHeight})',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LabeledNumberField(
                    fieldKey: '${node.id}.x',
                    label: strings.x,
                    value: node.rect.x * canvas.referenceWidth,
                    onSubmitted: (value) => updatePixelRect(x: value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LabeledNumberField(
                    fieldKey: '${node.id}.y',
                    label: strings.y,
                    value: node.rect.y * canvas.referenceHeight,
                    onSubmitted: (value) => updatePixelRect(y: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LabeledNumberField(
                    fieldKey: '${node.id}.width',
                    label: strings.width,
                    value: node.rect.width * canvas.referenceWidth,
                    onSubmitted: (value) => updatePixelRect(width: value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LabeledNumberField(
                    fieldKey: '${node.id}.height',
                    label: strings.height,
                    value: node.rect.height * canvas.referenceHeight,
                    onSubmitted: (value) => updatePixelRect(height: value),
                  ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: strings.layout,
          children: [
            _IntField(
              label: strings.z,
              value: node.z,
              onChanged: (value) =>
                  controller.updateSelected((node) => node.copyWith(z: value)),
            ),
            const SizedBox(height: 8),
            _IntField(
              label: strings.renderOrder,
              value: node.renderOrder,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(renderOrder: value),
              ),
            ),
            const SizedBox(height: 8),
            _IntField(
              label: strings.focusOrder,
              value: node.focusOrder,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(focusOrder: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransformTab extends StatelessWidget {
  const _TransformTab({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    void update(SceneTransform transform) {
      controller.updateSelected((node) => node.copyWith(transform: transform));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.transform,
          children: [
            LabeledSlider(
              label: strings.rotateZ,
              value: node.transform.rotationZ,
              min: -180,
              max: 180,
              onChanged: (value) =>
                  update(node.transform.copyWith(rotationZ: value)),
            ),
            LabeledSlider(
              label: strings.rotateX,
              value: node.transform.rotationX,
              min: -180,
              max: 180,
              onChanged: (value) =>
                  update(node.transform.copyWith(rotationX: value)),
            ),
            LabeledSlider(
              label: strings.rotateY,
              value: node.transform.rotationY,
              min: -180,
              max: 180,
              onChanged: (value) =>
                  update(node.transform.copyWith(rotationY: value)),
            ),
            LabeledSlider(
              label: strings.perspective,
              value: node.transform.perspective,
              min: -0.01,
              max: 0.01,
              onChanged: (value) =>
                  update(node.transform.copyWith(perspective: value)),
            ),
            LabeledSlider(
              label: strings.scaleX,
              value: node.transform.scaleX,
              min: 0.1,
              max: 3,
              onChanged: (value) =>
                  update(node.transform.copyWith(scaleX: value)),
            ),
            LabeledSlider(
              label: strings.scaleY,
              value: node.transform.scaleY,
              min: 0.1,
              max: 3,
              onChanged: (value) =>
                  update(node.transform.copyWith(scaleY: value)),
            ),
            LabeledSlider(
              label: strings.moveX,
              value: node.transform.translateX,
              min: -0.5,
              max: 0.5,
              onChanged: (value) =>
                  update(node.transform.copyWith(translateX: value)),
            ),
            LabeledSlider(
              label: strings.moveY,
              value: node.transform.translateY,
              min: -0.5,
              max: 0.5,
              onChanged: (value) =>
                  update(node.transform.copyWith(translateY: value)),
            ),
            LabeledSlider(
              label: strings.pivotX,
              value: node.transform.pivotX,
              min: 0,
              max: 1,
              onChanged: (value) =>
                  update(node.transform.copyWith(pivotX: value)),
            ),
            LabeledSlider(
              label: strings.pivotY,
              value: node.transform.pivotY,
              min: 0,
              max: 1,
              onChanged: (value) =>
                  update(node.transform.copyWith(pivotY: value)),
            ),
          ],
        ),
      ],
    );
  }
}

class _VisibilityTab extends StatelessWidget {
  const _VisibilityTab({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.visibility,
          children: [
            ConditionEditor(
              condition: node.visibleWhen,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(visibleWhen: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PropertiesTab extends StatelessWidget {
  const _PropertiesTab({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.properties,
          children: [_PropertiesEditor(controller: controller, node: node)],
        ),
      ],
    );
  }
}

class _IdField extends StatelessWidget {
  const _IdField({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(node.id),
      initialValue: node.id,
      decoration: InputDecoration(
        labelText: EditorStringsScope.of(context).id,
        isDense: true,
      ),
      onFieldSubmitted: (value) {
        final id = value.trim();
        final document = controller.document;
        if (document == null || id.isEmpty) {
          return;
        }
        final taken = document.nodes.any(
          (candidate) => candidate.id == id && candidate.id != node.id,
        );
        if (taken) {
          return;
        }
        controller.updateSelected((node) => node.copyWith(id: id));
      },
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label:$value'),
      initialValue: value.toString(),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onFieldSubmitted: (text) {
        final parsed = int.tryParse(text.trim());
        if (parsed != null) {
          onChanged(parsed);
        }
      },
    );
  }
}

class _PropertiesEditor extends StatelessWidget {
  const _PropertiesEditor({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in node.properties.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(entry.key, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: ValueKey('${node.id}:${entry.key}:${entry.value}'),
                    initialValue: entry.value,
                    decoration: const InputDecoration(isDense: true),
                    onFieldSubmitted: (value) => controller.updateSelected(
                      (node) => node.copyWith(
                        properties: {...node.properties, entry.key: value},
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.removeProperty,
                  onPressed: () => controller.updateSelected(
                    (node) => node.copyWith(
                      properties: {
                        for (final candidate in node.properties.entries)
                          if (candidate.key != entry.key)
                            candidate.key: candidate.value,
                      },
                    ),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => controller.updateSelected(
            (node) => node.copyWith(
              properties: {
                ...node.properties,
                _uniqueKey(node.properties, 'property'): '',
              },
            ),
          ),
          icon: const Icon(Icons.add),
          label: Text(strings.addProperty),
        ),
      ],
    );
  }
}

String _uniqueKey(Map<String, String> properties, String base) {
  var index = 1;
  while (properties.containsKey('$base$index')) {
    index++;
  }
  return '$base$index';
}
