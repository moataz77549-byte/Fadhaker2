"use client";

import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Provider = {
  id: string; name: string; slug: string; rights_status: string;
  commercial_use_status: string; production_enabled: boolean;
  health_status: string; verified_at: string | null; last_success_at: string | null;
};
type SyncRun = {
  id: string; provider_id: string; dataset: string | null; status: string;
  finished_at: string | null; fetched_count: number; inserted_count: number;
  updated_count: number; error_code: string | null;
  metadata: { duration_ms?: number } | null;
};
type Status = { providers: Provider[]; runs: SyncRun[];
  counts: { translations: number; hadiths: number } };
type ReviewDataset = "translations" | "hadiths";
type ReviewRow = {
  id: string; provider_id: string; is_active: boolean; source_url: string;
  title?: string | null; language_code?: string; translation_key?: string;
  surah_number?: number; ayah_number?: number; translation_text?: string;
  source_version?: string; hadith_text?: string; narrator?: string | null;
  grade?: string | null; reference?: string | null; verified_at?: string | null;
};
type ReviewResult = { dataset: ReviewDataset; items: ReviewRow[];
  count: number; limit: number; offset: number };

async function providerRequest(
  method: "GET" | "POST",
  input?: object,
  query?: URLSearchParams,
): Promise<unknown> {
  if (!supabase || !process.env.NEXT_PUBLIC_SUPABASE_URL) throw Error("إعداد الاتصال غير مكتمل");
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw Error("سجّل الدخول إلى لوحة الإدارة");
  const suffix = query && query.size > 0 ? `?${query.toString()}` : "";
  const response = await fetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/provider-sync${suffix}`,
    {
    method,
    headers: { Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/json" },
    body: input ? JSON.stringify(input) : undefined,
  });
  if (!response.ok) throw Error(response.status === 401
    ? "لا تملك صلاحية إدارة مزامنة المصادر" : "تعذّر الوصول إلى خدمة المصادر");
  return response.json();
}

export default function ProvidersPage() {
  const [status, setStatus] = useState<Status | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [provider, setProvider] = useState("quranenc");
  const [translationKey, setTranslationKey] = useState("english_saheeh");
  const [categoryId, setCategoryId] = useState("1");
  const [dryRun, setDryRun] = useState(true);
  const [result, setResult] = useState<string | null>(null);
  const [reviewDataset, setReviewDataset] = useState<ReviewDataset>("translations");
  const [review, setReview] = useState<ReviewResult | null>(null);
  const [reviewBusy, setReviewBusy] = useState(false);
  const refresh = useCallback(async () => {
    try {
      setStatus(await providerRequest("GET") as Status);
      setError(null);
    } catch (e) { setError(e instanceof Error ? e.message : "فشل التحميل"); }
  }, []);
  useEffect(() => { void refresh(); }, [refresh]);

  async function syncNow() {
    setBusy(true); setResult(null); setError(null);
    try {
      const input = provider === "quranenc"
        ? { provider, dataset: "translations", translationKey, limitSurahs: 1, dryRun }
        : { provider, dataset: "hadith", categoryId, language: "ar", perPage: 5, dryRun };
      const run = await providerRequest("POST", input) as { run_id: string; fetched: number;
        inserted: number; updated: number; unchanged: number; status: string };
      setResult(`العملية ${run.status}: فُحص ${run.fetched}، جديد ${run.inserted}، محدّث ${run.updated}، دون تغيير ${run.unchanged}.`);
      await refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "فشلت المزامنة"); }
    finally { setBusy(false); }
  }

  async function loadReview() {
    setReviewBusy(true); setError(null);
    try {
      const query = new URLSearchParams({
        review: reviewDataset,
        limit: "20",
        offset: "0",
      });
      setReview(await providerRequest("GET", undefined, query) as ReviewResult);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّرت مراجعة المحتوى");
    } finally {
      setReviewBusy(false);
    }
  }

  return <section dir="rtl" style={{ maxWidth: 1100, margin: "auto" }}>
    <h1>المصادر والمزامنة</h1>
    <p>تُعرض حقوق المصادر وحالة المزامنة. المحتوى المستورد يبقى محجوبًا حتى الموافقة والمراجعة.</p>
    {error && <p role="alert" style={{ color: "#f87171" }}>{error}</p>}
    <button onClick={() => void refresh()}>تحديث الحالة</button>
    <p>الترجمات المخزنة: {status?.counts.translations ?? "—"} · الأحاديث المخزنة: {status?.counts.hadiths ?? "—"}</p>
    <div style={{ overflowX: "auto" }}>
      <table style={{ width: "100%", borderSpacing: 12, textAlign: "right" }}>
        <thead><tr><th>المصدر</th><th>الحقوق</th><th>التجاري</th><th>النشر</th><th>الصحة</th><th>آخر نجاح</th></tr></thead>
        <tbody>{status?.providers.map(p => <tr key={p.id}>
          <td>{p.name}</td><td>{p.rights_status}</td><td>{p.commercial_use_status}</td>
          <td>{p.production_enabled ? "مفعّل" : "موقوف"}</td><td>{p.health_status}</td>
          <td>{p.last_success_at ? new Date(p.last_success_at).toLocaleString("ar") : "—"}</td>
        </tr>)}</tbody>
      </table>
    </div>
    <h2>مزامنة عينة محدودة</h2>
    <label>المصدر <select value={provider} onChange={e => setProvider(e.target.value)}>
      <option value="quranenc">QuranEnc</option><option value="hadeethenc">HadeethEnc</option>
    </select></label>{" "}
    {provider === "quranenc" ? <label>مفتاح الترجمة <input value={translationKey}
      onChange={e => setTranslationKey(e.target.value)} /></label> :
      <label>رقم التصنيف <input value={categoryId}
        onChange={e => setCategoryId(e.target.value)} /></label>}{" "}
    <label><input type="checkbox" checked={dryRun} onChange={e => setDryRun(e.target.checked)} /> فحص دون تخزين</label>{" "}
    <button disabled={busy} onClick={() => void syncNow()}>{busy ? "جارٍ الفحص…" : "زامن الآن"}</button>
    {result && <p role="status">{result}</p>}
    <h2>مراجعة المحتوى المستورد</h2>
    <p style={{ color: "#9DAEC6" }}>
      عرض للمعاينة فقط. لا تُفعّل أي مادة من هنا، ولا يتجاوز هذا العرض بوابة حقوق المصدر.
    </p>
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <select value={reviewDataset}
        onChange={e => setReviewDataset(e.target.value as ReviewDataset)}>
        <option value="translations">ترجمات القرآن</option>
        <option value="hadiths">الأحاديث</option>
      </select>
      <button disabled={reviewBusy} onClick={() => void loadReview()}>
        {reviewBusy ? "جارٍ التحميل…" : "عرض عينة المراجعة"}
      </button>
      {review && <span>الإجمالي المخزن: {review.count}</span>}
    </div>
    {review && <div style={{ display: "grid", gap: 12, marginTop: 12 }}>
      {review.items.map(item => <article key={item.id}
        style={{ border: "1px solid #243B6B", borderRadius: 8, padding: 12 }}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
          <strong>{item.title || (review.dataset === "translations"
            ? `سورة ${item.surah_number} · آية ${item.ayah_number}`
            : "حديث")}</strong>
          <span>{item.is_active ? "منشور" : "محجوب"}</span>
        </div>
        {review.dataset === "translations"
          ? <p style={{ whiteSpace: "pre-wrap" }}>{item.translation_text}</p>
          : <p style={{ whiteSpace: "pre-wrap" }}>{item.hadith_text}</p>}
        <div style={{ color: "#9DAEC6", fontSize: "0.8rem" }}>
          {item.language_code || "—"}
          {item.source_version ? ` · الإصدار ${item.source_version}` : ""}
          {item.grade ? ` · الدرجة: ${item.grade}` : ""}
          {item.reference ? ` · ${item.reference}` : ""}
          {item.verified_at ? " · تمت المراجعة" : ""}
        </div>
        <a href={item.source_url} target="_blank" rel="noreferrer"
          style={{ color: "#2E9E9E", fontSize: "0.8rem" }}>فتح المصدر الأصلي</a>
      </article>)}
      {review.items.length === 0 && <p>لا توجد مواد مستوردة في هذه المجموعة حاليًا.</p>}
    </div>}
        <h2>سجل المزامنة</h2>
    <div style={{ overflowX: "auto" }}><table style={{ width: "100%", borderSpacing: 12, textAlign: "right" }}>
      <thead><tr><th>المصدر</th><th>البيانات</th><th>الحالة</th><th>فُحص</th><th>جديد</th><th>خطأ</th><th>المدة</th></tr></thead>
      <tbody>{status?.runs.map(run => <tr key={run.id}>
        <td>{status.providers.find(p => p.id === run.provider_id)?.name ?? "—"}</td>
        <td>{run.dataset ?? "محطات"}</td><td>{run.status}</td>
        <td>{run.fetched_count ?? 0}</td><td>{run.inserted_count ?? 0}</td>
        <td>{run.error_code ?? "—"}</td><td>{run.metadata?.duration_ms ?? "—"} ms</td>
      </tr>)}</tbody>
    </table></div>
  </section>;
}
