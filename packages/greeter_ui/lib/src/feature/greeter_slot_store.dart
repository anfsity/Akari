import 'package:flutter/foundation.dart';

import 'greeter_slots.dart';
import 'greeter_state.dart';

class _SlotChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Projects durable [GreeterState] updates into region listenables and fires
/// [slotChanges] once after all slots settle.
class GreeterSlotStore {
  final _SlotChangeNotifier _slotChanges = _SlotChangeNotifier();
  final ValueNotifier<ServiceSlots> _serviceSlots = ValueNotifier(const (
    mode: ServiceMode.starting,
    error: null,
  ));
  final ValueNotifier<AuthPromptSlots> _authPromptSlots = ValueNotifier((
    mode: AuthMode.userSelection,
    selectedUser: null,
    prompt: null,
    error: null,
    promptError: null,
  ));
  final ValueNotifier<AccountPickerSlots> _accountPickerSlots = ValueNotifier(
    AccountPickerSlots(users: const [], selected: null, canSelect: false),
  );
  final ValueNotifier<SessionPickerSlots> _sessionPickerSlots = ValueNotifier(
    SessionPickerSlots(
      mode: CatalogMode.empty,
      sessions: const [],
      selected: null,
      error: null,
    ),
  );
  final ValueNotifier<PowerSlots> _powerSlots = ValueNotifier(const (
    mode: PowerMode.idle,
    error: null,
  ));
  final ValueNotifier<bool> _dormantSlots = ValueNotifier(true);

  Listenable get slotChanges => _slotChanges;

  ValueListenable<ServiceSlots> get serviceSlots => _serviceSlots;

  ValueListenable<AuthPromptSlots> get authPromptSlots => _authPromptSlots;

  ValueListenable<AccountPickerSlots> get accountPickerSlots =>
      _accountPickerSlots;

  ValueListenable<SessionPickerSlots> get sessionPickerSlots =>
      _sessionPickerSlots;

  ValueListenable<PowerSlots> get powerSlots => _powerSlots;

  ValueListenable<bool> get dormantSlots => _dormantSlots;

  void sync(GreeterState next, {required bool canSelectUser}) {
    // ValueNotifier compares semantic slot equality before notifying, so
    // unrelated transitions do not rebuild every region of the scene.
    var slotsChanged = false;
    slotsChanged |= _setSlot(_serviceSlots, (
      mode: next.serviceMode,
      error: next.serviceError,
    ));
    slotsChanged |= _setSlot(_authPromptSlots, (
      mode: next.authMode,
      // Account selection belongs to its picker until authentication starts;
      // hiding it here keeps the prompt region from presenting a partial flow.
      selectedUser: next.authMode == AuthMode.userSelection
          ? null
          : next.selectedUser,
      prompt: next.prompt,
      error: next.authError,
      promptError: next.promptError,
    ));
    slotsChanged |= _setSlot(
      _accountPickerSlots,
      AccountPickerSlots(
        users: next.users,
        selected: next.selectedUser,
        canSelect: canSelectUser,
      ),
    );
    slotsChanged |= _setSlot(
      _sessionPickerSlots,
      SessionPickerSlots(
        mode: next.catalogMode,
        sessions: next.sessions,
        selected: next.selectedSession,
        error: next.catalogError,
      ),
    );
    slotsChanged |= _setSlot(_powerSlots, (
      mode: next.powerMode,
      error: next.powerError,
    ));
    slotsChanged |= _setSlot(_dormantSlots, next.dormant);
    if (slotsChanged) {
      _slotChanges.notify();
    }
  }

  static bool _setSlot<T>(ValueNotifier<T> slot, T next) {
    if (slot.value == next) {
      return false;
    }
    slot.value = next;
    return true;
  }

  void dispose() {
    _slotChanges.dispose();
    _serviceSlots.dispose();
    _authPromptSlots.dispose();
    _accountPickerSlots.dispose();
    _sessionPickerSlots.dispose();
    _powerSlots.dispose();
    _dormantSlots.dispose();
  }
}
