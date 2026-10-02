/// Transient UI work that must not replay whenever a state slot rebuilds.
/// Consumers subscribe before dispatching commands; this broadcast stream
/// retains no history for later subscribers.
sealed class FeatureEffect {
  const FeatureEffect();
}

class RequestFocusEffect extends FeatureEffect {
  const RequestFocusEffect(this.field);

  final String field;
}

class ShowNoticeEffect extends FeatureEffect {
  const ShowNoticeEffect(this.message, {this.isError = false});

  final String message;
  final bool isError;
}

class ExitAfterHandoffEffect extends FeatureEffect {
  const ExitAfterHandoffEffect();
}
