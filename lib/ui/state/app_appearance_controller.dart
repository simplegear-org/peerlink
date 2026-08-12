import 'package:flutter/foundation.dart';

import '../../core/runtime/storage_service.dart';
import '../theme/app_appearance.dart';
import '../theme/app_theme.dart';

class AppAppearanceController extends ChangeNotifier {
  static const String _storageKey = 'app_appearance';

  final StorageService storage;

  AppAppearance _current = AppAppearance.icon1;

  AppAppearanceController({required this.storage});

  AppAppearance get current => _current;

  Future<void> initialize() async {
    final raw = storage.getSettings().get(_storageKey) as String?;
    _current = AppAppearanceX.fromStorageKey(raw);
    AppTheme.applyAppearance(_current);
  }

  Future<void> select(AppAppearance appearance) async {
    if (_current == appearance) {
      return;
    }
    _current = appearance;
    AppTheme.applyAppearance(appearance);
    notifyListeners();
    await storage.getSettings().put(_storageKey, appearance.storageKey);
  }
}
