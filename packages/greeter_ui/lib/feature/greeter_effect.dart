/// Transient UI work that must not replay whenever a state slot rebuilds.
/// Consumers subscribe before dispatching commands; this broadcast stream
/// retains no history for later subscribers.
sealed class FeatureEffect {
  const FeatureEffect();
}

class FocusCredentialEffect extends FeatureEffect {
  const FocusCredentialEffect();
}

class ClearCredentialEffect extends FeatureEffect {
  const ClearCredentialEffect();
}

class ShowErrorNoticeEffect extends FeatureEffect {
  const ShowErrorNoticeEffect(this.message);

  final String message;
}

class ExitAfterHandoffEffect extends FeatureEffect {
  const ExitAfterHandoffEffect();
}
