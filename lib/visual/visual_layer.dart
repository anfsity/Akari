import 'package:flutter/widgets.dart';

/// Base type for concrete background and ambient visual implementations.
///
/// Concrete visuals consume semantic slots and never access Feature or D-Bus.
abstract class VisualLayer extends StatelessWidget {
  const VisualLayer({super.key});
}
