import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

abstract class BackgroundRenderer {
  const BackgroundRenderer();

  Widget build(BuildContext context, SceneBackground background);
}
