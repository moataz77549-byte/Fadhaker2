import { supabase } from './supabase';

/**
 * طبقة الوصول إلى جدول app.app_config.
 *
 * كل القراءات والكتابات هنا حقيقية عبر Supabase. لا توجد رسائل نجاح
 * وهمية: أي فشل في الحفظ يُعرض كخطأ صريح في الواجهة.
 *
 * قيود الجدول (من الـ migrations):
 * - key يطابق ^[a-z][a-z0-9_]*$
 * - value_type ∈ BOOLEAN | INTEGER | STRING | URL | UUID | JSON
 */

export type ConfigValueType = 'BOOLEAN' | 'INTEGER' | 'STRING' | 'URL' | 'UUID' | 'JSON';

export interface AppConfigRow {
  key: string;
  /** القيمة مفكوكة من jsonb */
  value: unknown;
  value_type: ConfigValueType;
  is_public: boolean;
  description: string | null;
}

const KEY_PATTERN = /^[a-z][a-z0-9_]*$/;

export function assertConfigKey(key: string): void {
  if (!KEY_PATTERN.test(key)) {
    throw new Error(`مفتاح الإعداد غير صالح: ${key}`);
  }
}

/** قراءة صف واحد من app.app_config. تُرجع null عند غياب الصف. */
export async function fetchConfigRow(key: string): Promise<AppConfigRow | null> {
  if (!supabase) throw new Error('Supabase غير مُهيأ في هذه البيئة.');
  assertConfigKey(key);
  const { data, error } = await supabase
    .schema('app')
    .from('app_config')
    .select('key, value, value_type, is_public, description')
    .eq('key', key)
    .maybeSingle();
  if (error) throw new Error(`تعذّرت قراءة الإعداد «${key}»: ${error.message}`);
  return (data as AppConfigRow | null) ?? null;
}

/** قراءة عدة مفاتيح دفعة واحدة. */
export async function fetchConfigRows(keys: string[]): Promise<Record<string, AppConfigRow | null>> {
  if (!supabase) throw new Error('Supabase غير مُهيأ في هذه البيئة.');
  keys.forEach(assertConfigKey);
  const { data, error } = await supabase
    .schema('app')
    .from('app_config')
    .select('key, value, value_type, is_public, description')
    .in('key', keys);
  if (error) throw new Error(`تعذّرت قراءة الإعدادات: ${error.message}`);
  const result: Record<string, AppConfigRow | null> = {};
  for (const key of keys) result[key] = null;
  for (const row of (data ?? []) as AppConfigRow[]) result[row.key] = row;
  return result;
}

export interface SaveConfigInput {
  key: string;
  /** القيمة ككائن JS — تُحفظ كـ jsonb */
  value: unknown;
  valueType: ConfigValueType;
  isPublic: boolean;
  description?: string;
}

/**
 * حفظ (إدراج أو تحديث) صف في app.app_config.
 * الكتابة تخضع لـ RLS: تحتاج صلاحية settings.write وإلا رفضها الخادم
 * ويُعرض سبب الرفض للمشغّل بدل رسالة نجاح وهمية.
 */
export async function saveConfigRow(input: SaveConfigInput): Promise<AppConfigRow> {
  if (!supabase) throw new Error('Supabase غير مُهيأ في هذه البيئة.');
  assertConfigKey(input.key);
  const { data, error } = await supabase
    .schema('app')
    .from('app_config')
    .upsert(
      {
        key: input.key,
        value: input.value,
        value_type: input.valueType,
        is_public: input.isPublic,
        description: input.description ?? null,
      },
      { onConflict: 'key' },
    )
    .select('key, value, value_type, is_public, description')
    .single();
  if (error) throw new Error(`تعذّر حفظ الإعداد «${input.key}»: ${error.message}`);
  return data as AppConfigRow;
}
