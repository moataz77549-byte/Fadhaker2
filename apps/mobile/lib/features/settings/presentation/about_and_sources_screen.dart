import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/widgets/brand_mark.dart';

/// Public-facing provenance for content that is currently available in Fadhkur.
/// This list describes API linking separately from rights to rehost audio.
class AboutAndSourcesScreen extends StatelessWidget {
  const AboutAndSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصادر وعن التطبيق')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: FadhkurBrandMark(size: 72)),
          const SizedBox(height: 12),
          Center(
            child: Text(BrandConfig.nameAr,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          const SizedBox(height: 6),
          const Text(BrandConfig.taglineAr, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Text('مصادر المحتوى', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'تُعرض روابط المصادر وأدوارها بشفافية. إتاحة رابط بث عبر واجهة API '
            'لا تعني امتلاك التسجيل أو الإذن بإعادة استضافته.',
          ),
          const SizedBox(height: 12),
          const _SourceTile(
            title: 'القرآن والتفسير والتلاوات — Quran Foundation',
            detail: 'النص العثماني، بيانات الصفحات والأسطر (QCF V2)، وسوم التجويد، '
                'البحث، التفاسير، وملفات تلاوة الآيات تُطلب عبر خادم فذكر. '
                'لا تُخزَّن مفاتيح Quran Foundation السرية داخل التطبيق.',
            url: 'https://api-docs.quran.foundation/',
          ),
          const _SourceTile(
            title: 'الموضوعات القرآنية — Quranpedia',
            detail: 'تصنيف فهرسي/تفسيري مرتبط بمفاتيح الآيات، وليس جزءًا من نص القرآن. '
                'تُخزّن بيانات الموضوعات محليًا بعد المزامنة وتُحدّث عبر delta sync. '
                'الإصدار المرجعي وقت التكامل: 2026-09-24.',
            url: 'https://quranpedia.net/api-docs',
          ),
          const _SourceTile(
            title: 'المصحف المدني — مجمع الملك فهد / QCF',
            detail: 'الوضع الافتراضي الجديد يبني صفحات 1–604 من بيانات التخطيط النصي '
                'بدل تنزيل 604 صورة. صور QuranHub القديمة محفوظة مؤقتًا كمسار رجوع '
                'غير مفعّل افتراضيًا حتى اكتمال التحقق.',
            url: 'https://qurancomplex.gov.sa/',
          ),
          const _SourceTile(
            title: 'إذاعات MP3Quran',
            detail: 'روابط بث من API الرسمي. أجاز مالك التطبيق عرض روابط API الرسمية داخل التطبيق، '
                'ولا تُعاد استضافة ملفات الصوت. تُخفى المحطات غير السليمة.',
            url: 'https://www.mp3quran.net/ar/api',
          ),
          const _SourceTile(
            title: 'المواقيت عند الاتصال — AlAdhan',
            detail: 'تُستخدم واجهة المواقيت لسياق الإذاعة وبعض جداول الصلاة. '
                'تنبيهات الأذان تُحسب محليًا على الجهاز ولا تُبث في الإذاعة.',
            url: 'https://aladhan.com/calculation-methods',
          ),
          const _SourceTile(
            title: 'حديث اليوم — الأربعون النووية',
            detail: 'مجموعة محلية تعمل دون اتصال. عيّنة الموسوعة الجديدة قيد التحقق والإجازة قبل نشرها.',
          ),
          const SizedBox(height: 20),
          Text('مصادر قيد التكامل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('تظهر هذه المراجع للتعريف فقط؛ لم يُنشر محتواها الجديد في التطبيق بعد.'),
          const _SourceTile(
            title: 'QuranEnc — ترجمات معاني القرآن',
            detail: 'جرى اختبار استيراد محدود مع المصدر ورقم الإصدار والبصمة؛ الترجمة غير منشورة بعد لحين مراجعة الحقوق.',
            url: 'https://quranenc.com/ar/home/api',
          ),
          const _SourceTile(
            title: 'HadeethEnc — موسوعة الحديث',
            detail: 'جرى اختبار استيراد حديثين مع مصدرهما؛ لا تظهر العينة للعامة قبل مراجعة الإسناد والحقوق.',
            url: 'https://hadeethenc.com/api-docs/',
          ),
          const _SourceTile(
            title: 'Tanzil — مرجع تحقق',
            detail: 'مرجع للمقارنة فقط؛ لا يغيّر نص القرآن المعتمد.',
            url: 'https://tanzil.net/download/',
          ),
          const _SourceTile(
            title: 'الدرر السنية — بحث وتخريج',
            detail: 'مرجع بحث وتحقق، وليس نسخة من قاعدة الأحاديث.',
            url: 'https://dorar.net/',
          ),
          const _SourceTile(
            title: 'IslamHouse — مكتبة المحتوى',
            detail: 'المحاضرات والكتب قيد مراجعة العناصر والمراجع والحقوق.',
            url: 'https://islamhouse.com/',
          ),
          const _SourceTile(
            title: 'حصن المسلم — الأذكار',
            detail: 'قيد تدقيق النصوص والمراجع؛ لا تُعرض أذكار غير موثقة.',
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text(
            'حقوق الطبع والنشر لمعتز العلقمي - اليمن - تعز - 2026 م .',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'تُحفظ العلامات المرجعية وتفضيلات القراءة محليًا. '
            'قد يتطلب تشغيل الصوت والمحتوى الجديد اتصالًا بالإنترنت.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.title, required this.detail, this.url});

  final String title;
  final String detail;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.source_outlined),
        title: Text(title),
        subtitle: Text(detail),
        trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18),
        onTap: url == null
            ? null
            : () async {
                final uri = Uri.parse(url!);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
      ),
    );
  }
}
