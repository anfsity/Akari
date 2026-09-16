sealed class FeatureEffect {
  const FeatureEffect();
}

class RequestFocusEffect extends FeatureEffect {
  const RequestFocusEffect(this.field);

  final String field;
}

class ExitAfterHandoffEffect extends FeatureEffect {
  const ExitAfterHandoffEffect();
}
