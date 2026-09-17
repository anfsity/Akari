import 'package:flutter/material.dart';

import '../feature/greeter/greeter_slots.dart';
import 'visual_layer.dart';

const _backgroundAsset = 'assets/(139810879)年越し三人娘 『OIOI × 東方Project』.jpg';

class StaticBackgroundVisual extends VisualLayer {
  const StaticBackgroundVisual({required this.slots, super.key});

  final BackgroundSlots slots;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _backgroundAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(color: Color(0xff0d151a));
          },
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          color: _overlayColor(slots.mood),
        ),
        IgnorePointer(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.035 + slots.intensity * 0.025),
          ),
        ),
      ],
    );
  }

  Color _overlayColor(BackgroundMood mood) {
    return switch (mood) {
      BackgroundMood.calm => const Color(0x99050d12),
      BackgroundMood.active => const Color(0xb30b2730),
      BackgroundMood.success => const Color(0xb30c2b1e),
      BackgroundMood.error => const Color(0xbf35171e),
    };
  }
}
