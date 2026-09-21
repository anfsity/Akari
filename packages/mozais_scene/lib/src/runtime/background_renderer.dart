import 'package:flutter/widgets.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

abstract class BackgroundRenderer {
  const BackgroundRenderer();

  Widget build(BuildContext context, SceneBackground background);
}
