import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart';

import 'greeter_models.dart';

typedef ServiceSlots = ({ServiceMode mode, GreeterError? error});

typedef AuthPromptSlots = ({
  AuthMode mode,
  UserSummary? selectedUser,
  PromptState? prompt,
  GreeterError? error,
  String? promptError,
});

/// Value projection whose list equality suppresses unrelated slot notifications
/// even when the feature creates a new snapshot with the same users.
class AccountPickerSlots {
  AccountPickerSlots({
    required List<UserSummary> users,
    required this.selected,
    this.canSelect = false,
  }) : users = List.unmodifiable(users);

  final List<UserSummary> users;
  final UserSummary? selected;
  final bool canSelect;

  @override
  bool operator ==(Object other) {
    return other is AccountPickerSlots &&
        listEquals(other.users, users) &&
        other.selected == selected &&
        other.canSelect == canSelect;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(users), selected, canSelect);
}

/// Catalog projection with content equality, allowing refreshes that preserve
/// content to avoid rebuilding the picker solely due to a new list instance.
class SessionPickerSlots {
  SessionPickerSlots({
    required this.mode,
    required List<SessionSummary> sessions,
    required this.selected,
    required this.error,
  }) : sessions = List.unmodifiable(sessions);

  final CatalogMode mode;
  final List<SessionSummary> sessions;
  final SessionSummary? selected;
  final GreeterError? error;

  @override
  bool operator ==(Object other) {
    return other is SessionPickerSlots &&
        other.mode == mode &&
        listEquals(other.sessions, sessions) &&
        other.selected == selected &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(mode, Object.hashAll(sessions), selected, error);
}

typedef PowerSlots = ({PowerMode mode, GreeterError? error});

/// Maps the current greeter slots onto the scene predicate vocabulary.
Set<ScenePredicate> getActiveScenePredicates({
  required ServiceSlots service,
  required AuthPromptSlots auth,
  required AccountPickerSlots account,
  required SessionPickerSlots session,
  required PowerSlots power,
  required bool dormant,
}) {
  return <ScenePredicate>{
    if (dormant) ScenePredicate.isDormant,
    switch (service.mode) {
      ServiceMode.starting => ScenePredicate.isServiceStarting,
      ServiceMode.ready => ScenePredicate.isServiceReady,
      ServiceMode.unavailable => ScenePredicate.isServiceUnavailable,
    },
    switch (auth.mode) {
      AuthMode.userSelection => ScenePredicate.isUserSelection,
      AuthMode.prompting => ScenePredicate.isAuthPrompting,
      AuthMode.submitting => ScenePredicate.isAuthSubmitting,
      AuthMode.sessionSelection => ScenePredicate.isSessionSelection,
      AuthMode.handingOff => ScenePredicate.isHandingOff,
      AuthMode.error => ScenePredicate.isAuthError,
    },
    if (account.selected != null) ScenePredicate.hasSelectedUser,
    switch (session.mode) {
      CatalogMode.empty => ScenePredicate.isSessionEmpty,
      CatalogMode.loading => ScenePredicate.isSessionLoading,
      CatalogMode.ready => ScenePredicate.isSessionReady,
      CatalogMode.failed => ScenePredicate.isSessionFailed,
    },
    if (power.mode == PowerMode.executing) ScenePredicate.isPowerExecuting,
    if (power.error != null) ScenePredicate.hasPowerError,
  };
}
