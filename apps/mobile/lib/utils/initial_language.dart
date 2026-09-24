String initialLanguage({
  required String deviceLanguage,
  String? savedLanguage,
}) {
  if (savedLanguage == 'de' || savedLanguage == 'en') return savedLanguage!;
  return deviceLanguage == 'en' ? 'en' : 'de';
}
