insert into app.categories (slug, name_ar, name_en, icon_key, sort_order, is_active) values
  ('QURAN_GENERAL', 'القرآن العام', 'General Quran', 'quran', 10, true),
  ('RECITER', 'القراء', 'Reciters', 'mic', 20, true),
  ('TAFSEER', 'التفسير', 'Tafseer', 'book-open', 30, true),
  ('HADITH', 'الحديث', 'Hadith', 'books', 40, true),
  ('SEERAH', 'السيرة', 'Seerah', 'landmark', 50, true),
  ('SAHABAH', 'الصحابة', 'Companions', 'users', 60, true),
  ('ADHKAR', 'الأذكار', 'Adhkar', 'beads', 70, true),
  ('RUQYAH', 'الرقية الشرعية', 'Ruqyah', 'shield', 80, true),
  ('FATWA', 'الفتاوى', 'Fatwa', 'messages', 90, true),
  ('QURAN_TRANSLATION', 'ترجمات القرآن', 'Quran Translations', 'languages', 100, true),
  ('QURAN_SURAH', 'إذاعات السور', 'Surah Stations', 'list-audio', 110, true),
  ('LIVE_TV_AUDIO', 'البث التلفزيوني المباشر', 'Live TV Audio', 'radio-tower', 120, true),
  ('OTHER', 'أخرى', 'Other', 'grid', 999, true)
on conflict (slug) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  icon_key = excluded.icon_key,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active;
