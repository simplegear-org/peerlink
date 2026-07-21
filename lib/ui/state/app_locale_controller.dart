import 'package:flutter/foundation.dart';

import '../../core/runtime/storage_service.dart';
import '../localization/app_language.dart';

class AppLocaleController extends ChangeNotifier {
  static const String _storageKey = 'app_language';

  final StorageService storage;

  AppLanguage _current = AppLanguage.ru;

  AppLocaleController({required this.storage});

  AppLanguage get current => _current;

  Future<void> initialize() async {
    final raw = storage.getSettings().get(_storageKey) as String?;
    _current = AppLanguage.fromCode(raw);
  }

  Future<void> select(AppLanguage language) async {
    if (_current == language) {
      return;
    }
    _current = language;
    notifyListeners();
    await storage.getSettings().put(_storageKey, language.code);
  }
}
