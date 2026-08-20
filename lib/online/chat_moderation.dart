final _chatWordPattern = RegExp(
  r'[A-Za-zÀ-ÖØ-öø-ÿ]+(?:-[A-Za-zÀ-ÖØ-öø-ÿ]+)*',
);

final _profanityPatterns = <RegExp>[
  RegExp(r'^caralh(?:o|a|os|as|inho|inha|ao|oes)?$'),
  RegExp(r'^porr(?:a|as|inha|inhas|ao|oes)?$'),
  RegExp(r'^put(?:a|o|as|os|aria|arias|inha|inho|ona|ao)?$'),
  RegExp(r'^fod(?:a|as|ase|am|ao|er|eu|endo|ido|ida|idos|idas)?$'),
  RegExp(r'^merd(?:a|as|inha|inhas|ao|oes)?$'),
  RegExp(r'^bost(?:a|as|inha|inhas|ao|oes)?$'),
  RegExp(r'^(?:bucet|bocet)(?:a|as|inha|inhas|ao|oes)?$'),
  RegExp(r'^cacet(?:e|es|inho|inhos|ao|oes)?$'),
  RegExp(r'^desgrac(?:a|ado|ada|ados|adas|adinho|adinha)?$'),
  RegExp(r'^arrombad(?:o|a|os|as|inho|inha)?$'),
  RegExp(r'^viad(?:o|a|os|as|inho|inha)?$'),
  RegExp(r'^piroc(?:a|as|ao|oes|inha|inhas)?$'),
  RegExp(r'^cu(?:zao|zoes|zinho|zinhos)?$'),
  RegExp(r'^corn(?:o|a|os|as|inho|inha)?$'),
  RegExp(r'^vagabund(?:o|a|os|as)?$'),
  RegExp(r'^escrot(?:o|a|os|as)?$'),
  RegExp(r'^(?:fdp|pqp|vsf)$'),
];

String moderateChatText(String text) {
  return text.replaceAllMapped(_chatWordPattern, (match) {
    final word = match.group(0)!;
    if (!_isProfanity(word)) return word;
    return '${word[0]}${'*' * (word.length - 1)}';
  });
}

bool _isProfanity(String word) {
  final canonical = _removeDiacritics(
    word.toLowerCase().replaceAll('-', ''),
  );
  return _profanityPatterns.any((pattern) => pattern.hasMatch(canonical));
}

String _removeDiacritics(String value) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  var normalized = value;
  for (final replacement in replacements.entries) {
    normalized = normalized.replaceAll(replacement.key, replacement.value);
  }
  return normalized;
}
