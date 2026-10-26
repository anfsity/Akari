import 'package:scene/scene.dart';

/// Composition rules for one authored scene. A stable node ID identifies each
/// slot; its template supplies insertion defaults, not overrides for live edits.
class ThemeLayoutDefinition {
  const ThemeLayoutDefinition({
    required this.sceneId,
    required this.label,
    required this.slots,
    this.presets = const {},
  });

  final String sceneId;
  final String label;
  final List<ThemeLayoutSlot> slots;
  final Map<String, ThemeLayoutPreset> presets;

  static const presetProperty = 'layout';

  String? getPresetId(SceneDocument document) => presets.isEmpty
      ? null
      : document.themeProperties[presetProperty] ?? presets.keys.first;

  /// The document must have passed [validateDocument]. Insertion defaults are
  /// projected through the selected layout without changing authored nodes.
  List<ThemeLayoutSlot> getSlots(SceneDocument document) {
    if (presets.isEmpty) return slots;
    final preset = presets[getPresetId(document)]!;
    return [
      for (final slot in slots)
        if (preset.rects[slot.defaultNode.id] case final rect?)
          ThemeLayoutSlot(
            label: slot.label,
            isRequired: slot.isRequired,
            defaultNode: slot.defaultNode.copyWith(rect: rect),
          )
        else
          slot,
    ];
  }

  ThemeLayoutSlot? findSlot(String nodeId, {SceneDocument? document}) {
    for (final slot in document == null ? slots : getSlots(document)) {
      if (slot.defaultNode.id == nodeId) return slot;
    }
    return null;
  }

  /// Missing required slots are repairable authoring state. A conflicting
  /// component at a reserved ID is rejected rather than silently overwritten.
  void validateDocument(SceneDocument document) {
    if (document.id != sceneId) return;
    if (presets.isNotEmpty && !presets.containsKey(getPresetId(document))) {
      throw FormatException(
        'Layout "$label": unsupported preset "${getPresetId(document)}".',
      );
    }
    for (final node in document.nodes) {
      final slot = findSlot(node.id);
      if (slot != null && node.componentId != slot.defaultNode.componentId) {
        throw FormatException(
          'Layout "$label": slot "${node.id}" requires component '
          '"${slot.defaultNode.componentId}".',
        );
      }
    }
  }

  List<ThemeLayoutSlot> findMissingRequiredSlots(SceneDocument document) {
    if (document.id != sceneId) return const [];
    final ids = document.nodes.map((node) => node.id).toSet();
    return [
      for (final slot in getSlots(document))
        if (slot.isRequired && !ids.contains(slot.defaultNode.id)) slot,
    ];
  }

  /// Switching a skeleton resets layout-owned geometry, preserves content and
  /// optional omissions, and restores missing required controls. Ad-hoc nodes
  /// keep their geometry because the preset does not own their placement.
  SceneDocument getDocumentWithPreset(SceneDocument document, String presetId) {
    if (document.id != sceneId || !presets.containsKey(presetId)) {
      throw ArgumentError.value(
        presetId,
        'presetId',
        'Unavailable layout preset',
      );
    }
    final configured = document.copyWith(
      themeProperties: {...document.themeProperties, presetProperty: presetId},
    );
    final slots = {
      for (final slot in getSlots(configured)) slot.defaultNode.id: slot,
    };
    final ids = document.nodes.map((node) => node.id).toSet();
    return configured.copyWith(
      nodes: [
        for (final node in document.nodes)
          if (slots[node.id] case final slot?)
            node.copyWith(
              rect: slot.defaultNode.rect,
              transform: slot.defaultNode.transform,
            )
          else
            node,
        for (final slot in slots.values)
          if (slot.isRequired && !ids.contains(slot.defaultNode.id))
            slot.defaultNode,
      ],
    );
  }
}

/// One designed arrangement of a layout's existing semantic slots. An omitted
/// rectangle reuses the base slot position; component identity remains stable.
class ThemeLayoutPreset {
  const ThemeLayoutPreset({required this.label, this.rects = const {}});

  final String label;
  final Map<String, SceneRect> rects;
}

class ThemeLayoutSlot {
  const ThemeLayoutSlot({
    required this.label,
    required this.defaultNode,
    this.isRequired = false,
  });

  final String label;
  final SceneNode defaultNode;

  /// Studio protects present required slots and offers to add missing ones.
  /// This is a presence rule, not a guarantee about authentication behavior.
  final bool isRequired;
}
