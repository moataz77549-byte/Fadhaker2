import { Elysia } from 'elysia';
import { cors } from '@elysiajs/cors';
import { swagger } from '@elysiajs/swagger';
import * as fs from 'fs';
import * as path from 'path';

const app = new Elysia()
  .use(cors({
    origin: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
  }))
  .use(swagger({
    documentation: {
      info: {
        title: 'Fadhkur BFF API (Elysia)',
        version: '1.0.0',
        description: 'High-performance aggregation layer for Fadhkur platform'
      }
    }
  }))
  // 1. Health
  .get('/health', () => ({
    status: 'healthy',
    service: 'fadhkur-api-elysia',
    version: '1.0.0',
    edition: 'quran-uthmani-hafs-v1.0',
    timestamp: new Date().toISOString()
  }))

  // 2. Runtime Config Public Keys
  .get('/api/v1/runtime-config', () => ({
    feature_flags: {
      radio_enabled: true,
      offline_downloads: true,
      prayer_times: true,
      adhkar: true,
      learning_center: true
    },
    home_sections: ['featured_radio', 'prayer_times', 'daily_reading', 'stations_grid', 'reciters_carousel', 'offline_shelf'],
    min_supported_version: { android: '1.0.0', ios: '1.0.0' },
    maintenance: { is_active: false }
  }))

  // 3. Home Feed
  .get('/api/v1/home', () => ({
    dailyReading: {
      surahNumber: 18,
      surahNameArabic: 'سورة الكهف',
      startPage: 293,
      juzNumber: 15,
      recommendedVerses: '1-10'
    },
    featuredRadio: {
      slug: 'khashia',
      nameArabic: 'إذاعة التلاوات الخاشعة',
      currentTrack: 'سورة مريم — الشيخ عبد الباسط عبد الصمد',
      streamUrl: 'https://stream.fadhkur.app/live/khashia.mp3',
      bitrate: 128,
      listenersCount: 1420
    },
    prayerTimes: {
      city: 'الرياض',
      fajr: '04:32',
      sunrise: '05:51',
      dhuhr: '11:58',
      asr: '15:24',
      maghrib: '18:05',
      isha: '19:35'
    }
  }))

  // 4. Stations List
  .get('/api/v1/stations', () => ([
    {
      id: 'station-khashia',
      slug: 'khashia',
      titleArabic: 'إذاعة التلاوات الخاشعة',
      streamUrl: 'https://stream.fadhkur.app/live/khashia.mp3',
      fallbackStreamUrl: 'https://fallback.fadhkur.app/live/khashia.mp3',
      bitrateKbps: 128,
      isFeatured: true
    },
    {
      id: 'station-murattal',
      slug: 'murattal',
      titleArabic: 'إذاعة المصحف المرتل',
      streamUrl: 'https://stream.fadhkur.app/live/murattal.mp3',
      bitrateKbps: 128,
      isFeatured: true
    },
    {
      id: 'station-haramain',
      slug: 'haramain',
      titleArabic: 'إذاعة تلاوات الحرمين الشريفين',
      streamUrl: 'https://stream.fadhkur.app/live/haramain.mp3',
      bitrateKbps: 128,
      isFeatured: false
    },
    {
      id: 'station-minshawi',
      slug: 'minshawi',
      titleArabic: 'إذاعة الشيخ محمد صديق المنشاوي',
      streamUrl: 'https://stream.fadhkur.app/live/minshawi.mp3',
      bitrateKbps: 128,
      isFeatured: false
    }
  ]))

  // 5. Reciters List
  .get('/api/v1/reciters', () => ([
    {
      id: 'reciter-abdulbasit',
      canonicalSlug: 'abdulbasit-abdussamad',
      nameArabic: 'الشيخ عبد الباسط عبد الصمد',
      nameEnglish: 'Sheikh Abdulbasit Abdussamad',
      defaultRiwayah: 'المصحف المجود • حفص عن عاصم',
      surahsCount: 114,
      provider: 'مجمع الملك فهد / أرشيف إذاعة القرآن',
      audioQuality: '192 kbps • MP3'
    },
    {
      id: 'reciter-minshawi',
      canonicalSlug: 'mohamed-siddiq-el-minshawi',
      nameArabic: 'الشيخ محمد صديق المنشاوي',
      nameEnglish: 'Sheikh Mohamed Siddiq El-Minshawi',
      defaultRiwayah: 'المصحف المرتل • حفص عن عاصم',
      surahsCount: 114,
      provider: 'مجمع الملك فهد / أرشيف القاهرة',
      audioQuality: '192 kbps • MP3'
    },
    {
      id: 'reciter-husary',
      canonicalSlug: 'mahmoud-khalil-al-hussary',
      nameArabic: 'الشيخ محمود خليل الحصري',
      nameEnglish: 'Sheikh Mahmoud Khalil Al-Hussary',
      defaultRiwayah: 'المصحف المرتل • رواية ورش عن نافع',
      surahsCount: 114,
      provider: 'مجمع الملك فهد',
      audioQuality: '192 kbps • MP3'
    },
    {
      id: 'reciter-jaber',
      canonicalSlug: 'ali-abdullah-jaber',
      nameArabic: 'الشيخ علي عبد الله جابر',
      nameEnglish: 'Sheikh Ali Abdullah Jaber',
      defaultRiwayah: 'تلاوات الحرم المكي • حفص عن عاصم',
      surahsCount: 114,
      provider: 'أرشيف الحرم المكي الشريف',
      audioQuality: '192 kbps • MP3'
    }
  ]))

  // 6. Quran Surahs (Full 114 Surahs list)
  .get('/api/v1/quran/surahs', () => {
    try {
      const p = path.resolve(process.cwd(), 'data/quran/canonical/surahs.json');
      if (fs.existsSync(p)) {
        return JSON.parse(fs.readFileSync(p, 'utf8'));
      }
    } catch {
      // Fallback
    }

    return [
      { number: 1, nameArabic: 'الفاتحة', nameEnglish: 'Al-Fatihah', versesCount: 7, type: 'مكية', startPage: 1, juz: 1 },
      { number: 2, nameArabic: 'البقرة', nameEnglish: 'Al-Baqarah', versesCount: 286, type: 'مدنية', startPage: 2, juz: 1 },
      { number: 3, nameArabic: 'آل عمران', nameEnglish: 'Aal-E-Imran', versesCount: 200, type: 'مدنية', startPage: 50, juz: 3 },
      { number: 4, nameArabic: 'النساء', nameEnglish: "An-Nisa'", versesCount: 176, type: 'مدنية', startPage: 77, juz: 4 },
      { number: 5, nameArabic: 'المائدة', nameEnglish: "Al-Ma'idah", versesCount: 120, type: 'مدنية', startPage: 106, juz: 6 },
      { number: 6, nameArabic: 'الأنعام', nameEnglish: "Al-An'am", versesCount: 165, type: 'مكية', startPage: 128, juz: 7 },
      { number: 7, nameArabic: 'الأعراف', nameEnglish: "Al-A'raf", versesCount: 206, type: 'مكية', startPage: 151, juz: 8 },
      { number: 8, nameArabic: 'الأنفال', nameEnglish: 'Al-Anfal', versesCount: 75, type: 'مدنية', startPage: 177, juz: 9 },
      { number: 9, nameArabic: 'التوبة', nameEnglish: 'At-Tawbah', versesCount: 129, type: 'مدنية', startPage: 187, juz: 10 },
      { number: 10, nameArabic: 'يونس', nameEnglish: 'Yunus', versesCount: 109, type: 'مكية', startPage: 208, juz: 11 },
      { number: 11, nameArabic: 'هود', nameEnglish: 'Hud', versesCount: 123, type: 'مكية', startPage: 221, juz: 11 },
      { number: 12, nameArabic: 'يوسف', nameEnglish: 'Yusuf', versesCount: 111, type: 'مكية', startPage: 235, juz: 12 },
      { number: 13, nameArabic: 'الرعد', nameEnglish: "Ar-Ra'd", versesCount: 43, type: 'مدنية', startPage: 249, juz: 13 },
      { number: 14, nameArabic: 'إبراهيم', nameEnglish: 'Ibrahim', versesCount: 52, type: 'مكية', startPage: 255, juz: 13 },
      { number: 15, nameArabic: 'الحجر', nameEnglish: 'Al-Hijr', versesCount: 99, type: 'مكية', startPage: 262, juz: 14 },
      { number: 16, nameArabic: 'النحل', nameEnglish: 'An-Nahl', versesCount: 128, type: 'مكية', startPage: 267, juz: 14 },
      { number: 17, nameArabic: 'الإسراء', nameEnglish: 'Al-Isra', versesCount: 111, type: 'مكية', startPage: 282, juz: 15 },
      { number: 18, nameArabic: 'الكهف', nameEnglish: 'Al-Kahf', versesCount: 110, type: 'مكية', startPage: 293, juz: 15 },
      { number: 19, nameArabic: 'مريم', nameEnglish: 'Maryam', versesCount: 98, type: 'مكية', startPage: 305, juz: 16 },
      { number: 20, nameArabic: 'طه', nameEnglish: 'Taha', versesCount: 135, type: 'مكية', startPage: 312, juz: 16 },
      { number: 36, nameArabic: 'يس', nameEnglish: 'Ya-Sin', versesCount: 83, type: 'مكية', startPage: 440, juz: 22 },
      { number: 55, nameArabic: 'الرحمن', nameEnglish: 'Ar-Rahman', versesCount: 78, type: 'مدنية', startPage: 531, juz: 27 },
      { number: 67, nameArabic: 'الملك', nameEnglish: 'Al-Mulk', versesCount: 30, type: 'مكية', startPage: 562, juz: 29 },
      { number: 112, nameArabic: 'الإخلاص', nameEnglish: 'Al-Ikhlas', versesCount: 4, type: 'مكية', startPage: 604, juz: 30 },
      { number: 113, nameArabic: 'الفلق', nameEnglish: 'Al-Falaq', versesCount: 5, type: 'مكية', startPage: 604, juz: 30 },
      { number: 114, nameArabic: 'الناس', nameEnglish: 'An-Nas', versesCount: 6, type: 'مكية', startPage: 604, juz: 30 }
    ];
  })

  // 7. Quran Page View by Page Number (1 to 604)
  .get('/api/v1/quran/page/:page', ({ params, set }) => {
    const pageNum = parseInt(params.page, 10);
    if (isNaN(pageNum) || pageNum < 1 || pageNum > 604) {
      set.status = 400;
      return { error: 'Page number must be an integer between 1 and 604' };
    }

    const padded = pageNum.toString().padStart(3, '0');
    return {
      page: pageNum,
      totalPages: 604,
      imageUrl: `https://cdn.fadhkur.app/pages/uthmani/page_${padded}.png`,
      audioSampleUrl: `https://audio.fadhkur.app/pages/page_${padded}.mp3`,
      metadata: {
        edition: 'King Fahd Complex Madinah Uthmani Script',
        verifiedSha256ChecksumRequired: true
      }
    };
  })
  .listen(3001);

console.log(`Fadhkur Elysia BFF running at http://localhost:3001`);

export type App = typeof app;
