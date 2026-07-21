import '../../core/runtime/app_data_cleaner_service.dart';
import '../../core/runtime/app_storage_stats.dart';
import 'settings_server_config_service.dart';

class SettingsStorageMaintenanceService {
  final AppDataCleanerService dataCleaner;
  final SettingsServerConfigService serverConfigService;
  final Future<AppStorageBreakdown> Function() loadStorageBreakdownImpl;

  const SettingsStorageMaintenanceService({
    required this.dataCleaner,
    required this.serverConfigService,
    required this.loadStorageBreakdownImpl,
  });

  Future<AppStorageBreakdown> loadStorageBreakdown() {
    return loadStorageBreakdownImpl();
  }

  Future<void> clearManagedMediaStorage() {
    return dataCleaner.clearManagedMediaStorage();
  }

  Future<void> clearMessagesDatabase() {
    return dataCleaner.clearMessagesDatabase();
  }

  Future<void> clearSettingsAndServiceData() async {
    await dataCleaner.clearSettingsAndServiceData();
    await serverConfigService.clearSettingsOwnedServerData();
  }
}
