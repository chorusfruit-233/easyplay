enum DraughtsVariant {
  english,
  international,
  brazilian,
  russian,
  pool,
  italian,
  spanish,
  turkish,
}

extension DraughtsVariantX on DraughtsVariant {
  String get label => switch (this) {
    DraughtsVariant.english => '英式 / 美式',
    DraughtsVariant.international => '国际',
    DraughtsVariant.brazilian => '巴西',
    DraughtsVariant.russian => '俄罗斯',
    DraughtsVariant.pool => 'Pool',
    DraughtsVariant.italian => '意大利',
    DraughtsVariant.spanish => '西班牙',
    DraughtsVariant.turkish => '土耳其',
  };

  String get englishName => switch (this) {
    DraughtsVariant.english => 'English / American Checkers',
    DraughtsVariant.international => 'International Draughts',
    DraughtsVariant.brazilian => 'Brazilian Draughts',
    DraughtsVariant.russian => 'Russian Draughts',
    DraughtsVariant.pool => 'Pool Checkers',
    DraughtsVariant.italian => 'Italian Draughts',
    DraughtsVariant.spanish => 'Spanish Draughts',
    DraughtsVariant.turkish => 'Turkish Draughts',
  };
}
