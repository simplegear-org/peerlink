import '../../core/runtime/server_availability.dart';
import '../localization/app_strings.dart';
import 'settings_controller_models.dart';

class SettingsServerStatusPresenter {
  const SettingsServerStatusPresenter._();

  static SettingsServerState stateFromAvailability(
    ServerAvailability availability,
  ) {
    if (availability.isAvailable == true) {
      return SettingsServerState.connected;
    }
    if (availability.isAvailable == false) {
      return SettingsServerState.unavailable;
    }
    return SettingsServerState.connecting;
  }

  static int rank(SettingsServerState state) {
    switch (state) {
      case SettingsServerState.connected:
        return 0;
      case SettingsServerState.connecting:
        return 1;
      case SettingsServerState.unavailable:
        return 2;
      case SettingsServerState.paused:
        return 3;
    }
  }

  static String label(
    ServerAvailability availability, {
    required bool connected,
    AppStrings? strings,
  }) {
    final invalid = invalidAddressLabel(availability, strings: strings);
    if (invalid != null) {
      return invalid;
    }
    if (connected) {
      return strings?.serverConnectedStatus ?? 'подключен';
    }
    return availability.label(
      availableLabel: strings?.serverAvailable(active: false) ?? 'доступен',
      unavailableLabel:
          strings?.serverUnavailable(active: false) ?? 'недоступен',
      unknownLabel: strings?.serverCheckPending ?? 'ожидание проверки',
    );
  }

  static String? invalidAddressLabel(
    ServerAvailability availability, {
    AppStrings? strings,
  }) {
    if (availability.isAvailable == false &&
        availability.error?.trim() == 'некорректный адрес') {
      return strings?.invalidAddress ?? 'некорректный адрес';
    }
    return null;
  }
}
