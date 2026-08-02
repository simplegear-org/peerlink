import 'package:flutter/widgets.dart';

enum AppLanguage {
  en('en', 'EN', Locale('en')),
  zh('zh', 'ZH', Locale('zh')),
  es('es', 'ES', Locale('es')),
  ru('ru', 'RU', Locale('ru')),
  fr('fr', 'FR', Locale('fr'));

  final String code;
  final String shortLabel;
  final Locale locale;

  const AppLanguage(this.code, this.shortLabel, this.locale);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.ru,
    );
  }
}
