import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'preset_style.dart';

class PresetBackgroundRenderer extends BackgroundRenderer {
  const PresetBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) =>
      const PresetEnvironment();
}

/// The painted artwork has its own raster boundary. Only weather repaints on
/// each tick, so the soft light and botanical detail never need a per-frame
/// blur pass. Both layers share the same authored 1920 x 1080 coordinates.
class PresetEnvironment extends StatefulWidget {
  const PresetEnvironment({super.key});

  @override
  State<PresetEnvironment> createState() => _PresetEnvironmentState();
}

class _PresetEnvironmentState extends State<PresetEnvironment>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _weather;
  late final PresetWeatherPainter _painter;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _weather = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    );
    _painter = PresetWeatherPainter(_weather);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWeather();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _updateWeather();
  }

  void _updateWeather() {
    final animate =
        _visible &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_weather.isAnimating) {
      _weather.repeat();
    } else if (!animate && _weather.isAnimating) {
      _weather.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weather.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: CustomPaint(
                painter: PresetArtworkPainter(),
                isComplex: true,
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(painter: _painter, willChange: true),
            ),
          ],
        ),
      ),
    ),
  );
}

Path _getNightPath() => Path()
  ..moveTo(0, 920)
  ..lineTo(1920, 210)
  ..lineTo(1920, 1080)
  ..lineTo(0, 1080)
  ..close();

/// All artwork is authored in paths, gradients and seeded strokes. The static
/// blur softens streak edges once; the live rain uses only unfiltered lines.
class PresetArtworkPainter extends CustomPainter {
  const PresetArtworkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1920, size.height / 1080);
    canvas.drawColor(presetPaper, BlendMode.src);
    canvas.save();
    canvas.clipPath(_getNightPath());
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1920, 1080),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(650, 400),
          const Offset(1300, 1100),
          [const Color(0xff161520), const Color(0xff282733)],
        ),
    );
    final random = math.Random(19);
    for (var i = 0; i < 48; i++) {
      final y = 510 + random.nextDouble() * 1200;
      final x = -600 + random.nextDouble() * 1000;
      final length = 900 + random.nextDouble() * 1500;
      final width = 3 + random.nextDouble() * 36;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + length, y - length * .37),
        Paint()
          ..color = Color.fromRGBO(
            203,
            210,
            224,
            .025 + random.nextDouble() * .065,
          )
          ..strokeWidth = width
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * .7),
      );
    }
    // Fine broken strokes beneath the rain give the dark half a wet surface.
    final grain = Paint()
      ..color = const Color(0x12545b6e)
      ..strokeWidth = .65;
    for (var i = 0; i < 240; i++) {
      final x = random.nextDouble() * 1920;
      final y = random.nextDouble() * 1080;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 1, y + 5 + random.nextDouble() * 20),
        grain,
      );
    }
    canvas.restore();
    _paintBranch(canvas);
    canvas.restore();
  }

  void _paintBranch(Canvas canvas) {
    final stems = <(Path, double)>[
      (
        Path()
          ..moveTo(899, 604)
          ..cubicTo(846, 580, 836, 556, 825, 510)
          ..cubicTo(815, 483, 823, 464, 808, 443),
        4.0,
      ),
      (
        Path()
          ..moveTo(835, 546)
          ..cubicTo(818, 539, 802, 526, 798, 508)
          ..lineTo(788, 501),
        2.0,
      ),
      (
        Path()
          ..moveTo(819, 488)
          ..lineTo(835, 466)
          ..lineTo(848, 458),
        1.8,
      ),
      (
        Path()
          ..moveTo(820, 477)
          ..lineTo(802, 463)
          ..lineTo(795, 444),
        1.4,
      ),
      (
        Path()
          ..moveTo(813, 455)
          ..lineTo(822, 433),
        1.1,
      ),
      (
        Path()
          ..moveTo(855, 574)
          ..lineTo(872, 563)
          ..lineTo(877, 547),
        1.6,
      ),
      (
        Path()
          ..moveTo(902, 591)
          ..cubicTo(935, 567, 954, 539, 992, 511)
          ..lineTo(1009, 495),
        3.0,
      ),
      (
        Path()
          ..moveTo(953, 548)
          ..lineTo(944, 516)
          ..lineTo(940, 493),
        2.0,
      ),
      (
        Path()
          ..moveTo(946, 529)
          ..lineTo(931, 519),
        1.3,
      ),
      (
        Path()
          ..moveTo(979, 522)
          ..lineTo(986, 500),
        1.1,
      ),
      (
        Path()
          ..moveTo(1010, 561)
          ..cubicTo(1034, 549, 1058, 548, 1075, 570)
          ..cubicTo(1090, 596, 1082, 628, 1100, 655)
          ..lineTo(1118, 675),
        2.8,
      ),
      (
        Path()
          ..moveTo(1087, 620)
          ..lineTo(1064, 632)
          ..lineTo(1052, 651),
        1.4,
      ),
      (
        Path()
          ..moveTo(1098, 651)
          ..lineTo(1080, 671),
        1.1,
      ),
      (
        Path()
          ..moveTo(964, 580)
          ..lineTo(977, 603)
          ..lineTo(998, 618),
        1.5,
      ),
    ];
    for (final (path, width) in stems) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..color = const Color(0xff393342),
      );
      canvas.drawPath(
        path.shift(const Offset(-.8, -.4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * .24
          ..color = const Color(0x998c8294),
      );
    }
    final random = math.Random(82);
    for (final (x, y, radius, rotation) in <(double, double, double, double)>[
      (807, 447, 8, .2),
      (820, 514, 18, 1.1),
      (829, 532, 11, .4),
      (872, 568, 9, 2),
      (898, 590, 10, .8),
      (951, 594, 17, .6),
      (975, 583, 7, 1.8),
      (1068, 564, 14, 1.4),
      (1091, 606, 27, .2),
      (1073, 626, 10, 2.5),
    ]) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      for (var petal = 0; petal < 5; petal++) {
        canvas.save();
        canvas.rotate(petal * math.pi * .4);
        final r = radius * (.8 + random.nextDouble() * .35);
        final shape = Path()
          ..moveTo(0, 2)
          ..cubicTo(-r * .85, -r * .25, -r * .8, -r, -r * .17, -r)
          ..lineTo(0, -r * .86)
          ..cubicTo(r * .8, -r * 1.25, r * .7, -r * .25, 0, 2)
          ..close();
        canvas.drawPath(
          shape,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, -r), [
              const Color(0xffb5aaba),
              const Color(0xffeff1f6),
            ]),
        );
        canvas.drawPath(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .55
            ..color = const Color(0xff9e94a9),
        );
        for (var vein = -1; vein <= 1; vein++) {
          canvas.drawLine(
            const Offset(0, -2),
            Offset(vein * r * .18, -r * .78),
            Paint()
              ..strokeWidth = .45
              ..color = const Color(0x559387a4),
          );
        }
        canvas.restore();
      }
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6;
        final end = Offset(math.cos(angle), math.sin(angle)) * radius * .35;
        canvas.drawLine(
          Offset.zero,
          end,
          Paint()
            ..strokeWidth = .55
            ..color = const Color(0xff8e748c),
        );
        canvas.drawCircle(end, .85, Paint()..color = const Color(0xff786076));
      }
      canvas.restore();
    }
    for (final point in const [
      Offset(822, 433),
      Offset(848, 458),
      Offset(940, 493),
      Offset(1009, 495),
      Offset(986, 500),
      Offset(931, 519),
      Offset(1118, 675),
      Offset(1080, 671),
    ]) {
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(random.nextDouble() * 2 - 1);
      canvas.drawPath(
        Path()
          ..moveTo(0, 4)
          ..lineTo(-5, -7)
          ..quadraticBezierTo(0, -3, 5, -6)
          ..lineTo(1, 4)
          ..close(),
        Paint()..color = const Color(0xff897889),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PresetArtworkPainter oldDelegate) => false;
}

class PresetWeatherPainter extends CustomPainter {
  PresetWeatherPainter(this.time) : super(repaint: time);

  final Animation<double> time;
  static final _particles = List.generate(170, (i) {
    final random = math.Random(i * 37 + 1);
    return (
      x: random.nextDouble() * 2000,
      y: random.nextDouble() * 1160,
      size: 1.5 + random.nextDouble() * 4,
      cycles: 1 + random.nextInt(3),
      phase: random.nextDouble() * math.pi * 2,
    );
  });
  static final _rain = List.generate(720, (i) {
    final random = math.Random(i * 53 + 901);
    return (
      x: random.nextDouble() * 2160,
      y: random.nextDouble() * 1360,
      depth: random.nextDouble(),
      cycles: 36 + random.nextInt(29),
      length: i < 90
          ? 20 + random.nextDouble() * 38
          : 2 + random.nextDouble() * 15,
    );
  });
  static final _night = _getNightPath();
  static final _petal = Path()
    ..moveTo(-1, 0)
    ..quadraticBezierTo(-.2, -1.3, 1, -.3)
    ..quadraticBezierTo(.7, .8, -.6, .5)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1920, size.height / 1080);
    // Integer cycles make every position and flutter phase continuous when
    // the controller wraps, including the rain's faster independent motion.
    final progress = time.value;
    final angle = progress * math.pi * 2;
    final petalPaint = Paint();
    for (final p in _particles) {
      final x =
          (p.x + progress * 2000 + math.sin(angle * 9 + p.phase) * 22) % 2000 -
          40;
      final y = (p.y + progress * 1160 * p.cycles) % 1160 - 40;
      final light = y < 920 - x * 710 / 1920;
      petalPaint.color = light
          ? const Color(0x66737780)
          : const Color(0x225f6078);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + angle * 7);
      canvas.scale(
        p.size,
        p.size * (.25 + math.sin(angle * 19 + p.phase).abs() * .75),
      );
      canvas.drawPath(_petal, petalPaint);
      canvas.restore();
    }
    canvas.clipPath(_night);
    final rain = Paint()..strokeCap = StrokeCap.round;
    // Wrap beyond the canvas, including the longest streak's tail, so drops
    // re-enter from above instead of visibly teleporting across the dark field.
    for (final drop in _rain) {
      final y = (drop.y + progress * 1360 * drop.cycles) % 1360 - 140;
      final x = (drop.x + y * .12 + progress * 2160) % 2160 - 120;
      rain
        ..strokeWidth = .3 + drop.depth * .55
        ..color = Color.fromRGBO(185, 193, 213, .06 + drop.depth * .17);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + drop.length * .12, y + drop.length),
        rain,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PresetWeatherPainter oldDelegate) =>
      time != oldDelegate.time;
}

class PresetPresenceMotion extends SceneMotionBuilder {
  const PresetPresenceMotion();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    final eased = progress.drive(CurveTween(curve: Curves.easeInOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: spec.preset == SceneMotionPreset.fadeSlide
              ? const Offset(-.035, .12)
              : Offset.zero,
          end: Offset.zero,
        ).animate(eased),
        child: RepaintBoundary(child: child),
      ),
    );
  }
}
