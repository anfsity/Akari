enum StudioCanvasPreset {
  hd('HD', 1280, 720),
  fullHd('Full HD', 1920, 1080),
  qhd('QHD', 2560, 1440),
  uhd('4K UHD', 3840, 2160),
  portrait('Portrait', 1080, 1920),
  laptop('16:10', 1920, 1200),
  ultrawide('Ultrawide', 3440, 1440);

  const StudioCanvasPreset(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;
}
