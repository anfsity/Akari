import 'package:flutter/widgets.dart';

import '../model/scene_document.dart';

abstract class BackgroundRenderer {
  const BackgroundRenderer();

  Widget build(BuildContext context, SceneBackground background);
}
