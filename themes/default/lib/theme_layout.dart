import 'package:theme_sdk/theme_sdk.dart';

const _awake = SceneNot(ScenePredicateCondition(ScenePredicate.isDormant));
const _dormant = ScenePredicateCondition(ScenePredicate.isDormant);

// These insertion defaults survive edits to default.scene.json, including
// saved removals. Regenerating that document must not redefine available slots.
const terraceLayout = ThemeLayoutDefinition(
  sceneId: 'default',
  label: 'Terrace',
  presets: {
    'split': ThemeLayoutPreset(label: 'Terrace split'),
    'centered': ThemeLayoutPreset(
      label: 'Centered column',
      rects: {
        'clock': SceneRect(x: 0.34, y: 0.065, width: 0.32, height: 0.035),
        'scene_signature': SceneRect(
          x: 0.34,
          y: 0.12,
          width: 0.32,
          height: 0.028,
        ),
        'clock_time': SceneRect(x: 0.34, y: 0.3, width: 0.32, height: 0.16),
        'hello_world': SceneRect(x: 0.34, y: 0.485, width: 0.32, height: 0.095),
        'wake_hint': SceneRect(x: 0.34, y: 0.605, width: 0.32, height: 0.025),
        'entrance_heading': SceneRect(
          x: 0.3,
          y: 0.25,
          width: 0.4,
          height: 0.08,
        ),
        'entrance_caption': SceneRect(
          x: 0.3,
          y: 0.34,
          width: 0.4,
          height: 0.022,
        ),
        'account_picker': SceneRect(x: 0.3, y: 0.39, width: 0.4, height: 0.078),
        'session_picker': SceneRect(x: 0.3, y: 0.49, width: 0.4, height: 0.065),
        'credential_field': SceneRect(
          x: 0.3,
          y: 0.59,
          width: 0.34,
          height: 0.072,
        ),
        'primary_action': SceneRect(
          x: 0.648,
          y: 0.59,
          width: 0.052,
          height: 0.072,
        ),
        'status': SceneRect(x: 0.3, y: 0.69, width: 0.4, height: 0.045),
      },
    ),
  },
  slots: [
    ThemeLayoutSlot(
      label: 'Date',
      defaultNode: SceneNode(
        id: 'clock',
        componentId: 'dateTime',
        rect: SceneRect(x: 0.085, y: 0.065, width: 0.28, height: 0.035),
        renderOrder: 10,
        motion: SceneMotionPreset.fade,
        properties: {'variant': 'date'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Scene signature',
      defaultNode: SceneNode(
        id: 'scene_signature',
        componentId: 'terraceLabel',
        rect: SceneRect(x: 0.085, y: 0.12, width: 0.3, height: 0.028),
        renderOrder: 10,
        motion: SceneMotionPreset.fade,
        properties: {'text': 'AKARI / ABOVE THE CITY'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Standby clock',
      defaultNode: SceneNode(
        id: 'clock_time',
        componentId: 'terraceClock',
        rect: SceneRect(x: 0.085, y: 0.3, width: 0.32, height: 0.16),
        renderOrder: 10,
        motion: SceneMotionPreset.fadeSlide,
        visibleWhen: _dormant,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Standby greeting',
      defaultNode: SceneNode(
        id: 'hello_world',
        componentId: 'terraceLabel',
        rect: SceneRect(x: 0.09, y: 0.485, width: 0.32, height: 0.095),
        renderOrder: 10,
        motion: SceneMotionPreset.fadeSlide,
        visibleWhen: _dormant,
        properties: {'text': 'Hello World', 'variant': 'large'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Wake hint',
      defaultNode: SceneNode(
        id: 'wake_hint',
        componentId: 'terraceLabel',
        rect: SceneRect(x: 0.09, y: 0.605, width: 0.32, height: 0.025),
        renderOrder: 10,
        motion: SceneMotionPreset.fadeSlide,
        visibleWhen: _dormant,
        properties: {'text': 'PRESS ANY KEY TO SIGN IN'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Power actions',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'power_actions',
        componentId: 'powerActions',
        rect: SceneRect(x: 0.8, y: 0.055, width: 0.15, height: 0.06),
        renderOrder: 20,
        focusOrder: 60,
        motion: SceneMotionPreset.fade,
        interactive: true,
        properties: {'variant': 'icon-row'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Sign-in heading',
      defaultNode: SceneNode(
        id: 'entrance_heading',
        componentId: 'terraceLabel',
        rect: SceneRect(x: 0.085, y: 0.29, width: 0.4, height: 0.08),
        renderOrder: 40,
        motion: SceneMotionPreset.fadeSlide,
        visibleWhen: _awake,
        properties: {'text': 'Welcome back.', 'variant': 'large'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Sign-in caption',
      defaultNode: SceneNode(
        id: 'entrance_caption',
        componentId: 'terraceLabel',
        rect: SceneRect(x: 0.085, y: 0.377, width: 0.4, height: 0.022),
        renderOrder: 40,
        motion: SceneMotionPreset.fade,
        visibleWhen: _awake,
        properties: {'text': 'SIGN IN TO YOUR DESKTOP'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Account picker',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'account_picker',
        componentId: 'terraceAccount',
        rect: SceneRect(x: 0.085, y: 0.425, width: 0.4, height: 0.078),
        renderOrder: 40,
        focusOrder: 10,
        motion: SceneMotionPreset.fade,
        visibleWhen: _awake,
        interactive: true,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Session picker',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'session_picker',
        componentId: 'sessionPicker',
        rect: SceneRect(x: 0.085, y: 0.513, width: 0.4, height: 0.065),
        renderOrder: 40,
        focusOrder: 20,
        motion: SceneMotionPreset.fade,
        visibleWhen: _awake,
        interactive: true,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Credential input',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'credential_field',
        componentId: 'credentialField',
        rect: SceneRect(x: 0.085, y: 0.59, width: 0.34, height: 0.072),
        renderOrder: 40,
        focusOrder: 30,
        motion: SceneMotionPreset.fade,
        visibleWhen: _awake,
        interactive: true,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Sign-in action',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'primary_action',
        componentId: 'primaryAction',
        rect: SceneRect(x: 0.433, y: 0.59, width: 0.052, height: 0.072),
        renderOrder: 40,
        focusOrder: 40,
        motion: SceneMotionPreset.hoverLift,
        visibleWhen: SceneAll([
          _awake,
          SceneAny([
            ScenePredicateCondition(ScenePredicate.isAuthPrompting),
            ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
            ScenePredicateCondition(ScenePredicate.isSessionSelection),
            ScenePredicateCondition(ScenePredicate.isAuthError),
            ScenePredicateCondition(ScenePredicate.isServiceUnavailable),
          ]),
        ]),
        interactive: true,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Authentication status',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'status',
        componentId: 'status',
        rect: SceneRect(x: 0.085, y: 0.69, width: 0.4, height: 0.045),
        renderOrder: 40,
        motion: SceneMotionPreset.fade,
        properties: {'variant': 'inline'},
      ),
    ),
  ],
);
