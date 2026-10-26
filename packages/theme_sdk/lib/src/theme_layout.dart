import 'package:scene/scene.dart';

/// Composition rules for one authored scene. A stable node ID identifies each
/// slot; its template supplies insertion defaults, not overrides for live edits.
class ThemeLayoutDefinition {
  const ThemeLayoutDefinition({
    required this.sceneId,
    required this.label,
    required this.slots,
  });

  final String sceneId;
  final String label;
  final List<ThemeLayoutSlot> slots;

  ThemeLayoutSlot? findSlot(String nodeId) {
    for (final slot in slots) {
      if (slot.defaultNode.id == nodeId) return slot;
    }
    return null;
  }

  /// Missing required slots are repairable authoring state. A conflicting
  /// component at a reserved ID is rejected rather than silently overwritten.
  void validateDocument(SceneDocument document) {
    if (document.id != sceneId) return;
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
      for (final slot in slots)
        if (slot.isRequired && !ids.contains(slot.defaultNode.id)) slot,
    ];
  }
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
