import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

class CredentialField extends StatelessWidget {
  const CredentialField({
    required this.auth,
    required this.controller,
    required this.focusNode,
    this.textAlign = TextAlign.center,
    super.key,
  });

  final AuthPromptSlots auth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (auth.mode == AuthMode.submitting &&
        auth.prompt?.kind == PromptKind.info) {
      return Semantics(
        liveRegion: true,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _IdentityScan(),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Verifying identity...',
                  style: TextStyle(color: scheme.onSurface, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final enabled = auth.mode == AuthMode.prompting;
    final hintText = auth.mode == AuthMode.prompting
        ? auth.prompt?.text ?? 'Password'
        : 'Enter Password';
    final inputTheme = InputDecorationTheme.of(context);
    // Draw the border around the entire scene region while centering the native
    // text field inside it. The inner field disables its own decoration so the
    // authored region, rather than the text's intrinsic height, owns the surface.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final border = !enabled
            ? inputTheme.disabledBorder ?? inputTheme.border
            : focusNode.hasFocus
            ? inputTheme.focusedBorder ?? inputTheme.enabledBorder
            : inputTheme.enabledBorder;
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: inputTheme.fillColor,
            shape: border ?? InputBorder.none,
          ),
          child: child,
        );
      },
      child: Align(
        alignment: Alignment.center,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: auth.prompt?.kind == PromptKind.secret || !enabled,
          textInputAction: TextInputAction.done,
          textAlign: textAlign,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            filled: false,
            contentPadding: inputTheme.contentPadding,
            isDense: inputTheme.isDense,
          ),
        ),
      ),
    );
  }
}

class _IdentityScan extends StatefulWidget {
  const _IdentityScan();

  @override
  State<_IdentityScan> createState() => _IdentityScanState();
}

class _IdentityScanState extends State<_IdentityScan>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 0;
      return;
    }
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(40),
        painter: _IdentityScanPainter(
          animation: _animation,
          color: Theme.of(context).colorScheme.primary,
          animate: !MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}

/// Only the glyph repaints on each tick, keeping the prompt layout still while
/// authentication waits for the backend.
class _IdentityScanPainter extends CustomPainter {
  _IdentityScanPainter({
    required this.animation,
    required this.color,
    required this.animate,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final phase = animation.value * math.pi * 2;
    final gaze = animate ? math.sin(phase) * 1.5 : 0.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final frame = Path()
      ..moveTo(4, 13)
      ..lineTo(4, 9)
      ..quadraticBezierTo(4, 4, 9, 4)
      ..lineTo(13, 4)
      ..moveTo(27, 4)
      ..lineTo(31, 4)
      ..quadraticBezierTo(36, 4, 36, 9)
      ..lineTo(36, 13)
      ..moveTo(36, 27)
      ..lineTo(36, 31)
      ..quadraticBezierTo(36, 36, 31, 36)
      ..lineTo(27, 36)
      ..moveTo(13, 36)
      ..lineTo(9, 36)
      ..quadraticBezierTo(4, 36, 4, 31)
      ..lineTo(4, 27);
    canvas.drawPath(frame, paint);
    for (final x in [14.0, 26.0]) {
      canvas.drawLine(Offset(x + gaze, 14), Offset(x + gaze, 17), paint);
    }
    canvas.drawPath(
      Path()
        ..moveTo(20 + gaze, 18)
        ..lineTo(20 + gaze, 23)
        ..lineTo(18 + gaze, 23),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 27)
        ..quadraticBezierTo(20, 31, 26, 27),
      paint,
    );
    if (animate) {
      final scanY = 7 + (1 - math.cos(phase)) * 13;
      final scanRect = Rect.fromLTWH(7, scanY - 3, 26, 6);
      canvas.drawRect(
        scanRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0),
            ],
          ).createShader(scanRect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IdentityScanPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.color != color ||
      oldDelegate.animate != animate;
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    required this.service,
    required this.auth,
    required this.onRespond,
    required this.onStartSession,
    required this.onRetry,
    super.key,
  });

  final ServiceSlots service;
  final AuthPromptSlots auth;
  final VoidCallback onRespond;
  final VoidCallback onStartSession;
  final ValueChanged<GreeterRecovery> onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final error = auth.error;
    final action = service.mode == ServiceMode.unavailable
        ? (
            () => onRetry(GreeterRecovery.reconnectService),
            const Icon(Icons.refresh, size: 30),
          )
        : switch (auth.mode) {
            AuthMode.prompting => (
              onRespond,
              const Icon(Icons.arrow_forward, size: 30),
            ),
            AuthMode.sessionSelection => (
              onStartSession,
              const Icon(Icons.arrow_forward, size: 30),
            ),
            AuthMode.submitting => (
              null,
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
            AuthMode.error when error != null => (
              () => onRetry(error.recovery),
              const Icon(Icons.refresh, size: 30),
            ),
            AuthMode.error ||
            AuthMode.userSelection ||
            AuthMode.handingOff => null,
          };
    if (action == null) {
      return const SizedBox.shrink();
    }
    final (onPressed, icon) = action;

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.4),
            disabledForegroundColor: colorScheme.onPrimary.withValues(
              alpha: 0.5,
            ),
          ),
          child: icon,
        ),
      ),
    );
  }
}
