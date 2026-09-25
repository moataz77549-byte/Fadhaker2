"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * إدارة كتالوج محطات الإذاعة — كل العمليات حقيقية على جدول app.stations:
 * الاسم، رابط البث، الرابط البديل، الشعار، التفعيل/التعطيل الفوري (is_active)،
 * الترتيب (sort_order)، نوع البث (stream_type)، والتصنيف (النوع: مستمر/قارئ/تفسير/درس).
 */

interface StationRow {
  id: string;
  name_ar: string;
  name_en: string | null;
  stream_url: string;
  fallback_stream_url: string | null;
  logo_url: string | null;
  stream_type: string;
  station_source: string;
  is_active: boolean;
  is_featured: boolean;
  sort_order: number;
  health_status: string;
  category_id: string | null;
  categories: { slug: string; name_ar: string }[] | null;
}

function categoryOf(station: StationRow): { slug: string; name_ar: string } | null {
  const c = station.categories;
  if (Array.isArray(c) && c.length > 0) return c[0];
  return null;
}

interface CategoryRow {
  id: string;
  slug: string;
  name_ar: string;
}

interface StreamTypeRow {
  code: string;
  description: string;
}

interface Draft {
  name_ar: string;
  stream_url: string;
  fallback_stream_url: string;
  logo_url: string;
  stream_type: string;
  category_id: string;
  sort_order: string;
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "0.5rem 0.75rem",
  borderRadius: "6px",
  backgroundColor: "#0E1726",
  border: "1px solid #243B6B",
  color: "#F8F6F1",
  fontSize: "0.85rem",
};

const btnPrimary: React.CSSProperties = {
  backgroundColor: "#2E9E9E",
  color: "#fff",
  border: "none",
  padding: "0.5rem 1rem",
  borderRadius: "6px",
  fontWeight: 600,
  cursor: "pointer",
  fontSize: "0.85rem",
};

const btnGhost: React.CSSProperties = {
  backgroundColor: "transparent",
  color: "#9DAEC6",
  border: "1px solid #243B6B",
  padding: "0.5rem 1rem",
  borderRadius: "6px",
  cursor: "pointer",
  fontSize: "0.85rem",
};

function StationEditor({
  station,
  categories,
  streamTypes,
  onSaved,
  onCancel,
}: {
  station: StationRow;
  categories: CategoryRow[];
  streamTypes: StreamTypeRow[];
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState<Draft>({
    name_ar: station.name_ar,
    stream_url: station.stream_url,
    fallback_stream_url: station.fallback_stream_url ?? "",
    logo_url: station.logo_url ?? "",
    stream_type: station.stream_type,
    category_id: station.category_id ?? "",
    sort_order: String(station.sort_order),
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (k: keyof Draft) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setDraft((d) => ({ ...d, [k]: e.target.value }));

  const handleSave = async () => {
    if (!supabase) return;
    setError(null);
    const sortOrder = parseInt(draft.sort_order, 10);
    if (!draft.name_ar.trim()) {
      setError("اسم المحطة مطلوب.");
      return;
    }
    if (!/^https?:\/\/.+/i.test(draft.stream_url.trim())) {
      setError("رابط البث يجب أن يبدأ بـ http:// أو https://");
      return;
    }
    if (Number.isNaN(sortOrder) || sortOrder < 0) {
      setError("الترتيب يجب أن يكون عددًا صحيحًا غير سالب.");
      return;
    }
    setSaving(true);
    try {
      const { error: uerr } = await supabase
        .schema("app")
        .from("stations")
        .update({
          name_ar: draft.name_ar.trim(),
          stream_url: draft.stream_url.trim(),
          fallback_stream_url: draft.fallback_stream_url.trim() || null,
          logo_url: draft.logo_url.trim() || null,
          stream_type: draft.stream_type,
          category_id: draft.category_id || null,
          sort_order: sortOrder,
        })
        .eq("id", station.id);
      if (uerr) throw new Error(uerr.message);
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? `تعذّر الحفظ: ${e.message}` : "تعذّر الحفظ.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={{ backgroundColor: "#0E1726", borderRadius: "8px", padding: "1rem", marginTop: "0.75rem", border: "1px solid #243B6B" }}>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.75rem" }}>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6" }}>
          الاسم (عربي)
          <input style={inputStyle} value={draft.name_ar} onChange={set("name_ar")} />
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6" }}>
          الترتيب (sort_order)
          <input style={{ ...inputStyle, direction: "ltr" }} value={draft.sort_order} onChange={set("sort_order")} inputMode="numeric" />
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6", gridColumn: "1 / -1" }}>
          رابط البث (Stream URL)
          <input style={{ ...inputStyle, direction: "ltr", textAlign: "left" }} value={draft.stream_url} onChange={set("stream_url")} dir="ltr" />
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6", gridColumn: "1 / -1" }}>
          الرابط البديل (اختياري)
          <input style={{ ...inputStyle, direction: "ltr", textAlign: "left" }} value={draft.fallback_stream_url} onChange={set("fallback_stream_url")} dir="ltr" />
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6", gridColumn: "1 / -1" }}>
          الشعار (Logo URL — اختياري)
          <input style={{ ...inputStyle, direction: "ltr", textAlign: "left" }} value={draft.logo_url} onChange={set("logo_url")} dir="ltr" />
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6" }}>
          نوع البث
          <select style={inputStyle} value={draft.stream_type} onChange={set("stream_type")}>
            {streamTypes.map((t) => (
              <option key={t.code} value={t.code}>{t.code} — {t.description}</option>
            ))}
          </select>
        </label>
        <label style={{ fontSize: "0.8rem", color: "#9DAEC6" }}>
          التصنيف (يحدد نوع المحطة في التطبيق)
          <select style={inputStyle} value={draft.category_id} onChange={set("category_id")}>
            <option value="">— بدون تصنيف —</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>{c.name_ar} ({c.slug})</option>
            ))}
          </select>
        </label>
      </div>
      {error && <div style={{ color: "#FCA5A5", fontSize: "0.85rem", marginTop: "0.75rem" }}>⚠️ {error}</div>}
      <div style={{ display: "flex", gap: "0.75rem", marginTop: "1rem" }}>
        <button onClick={handleSave} disabled={saving} style={{ ...btnPrimary, opacity: saving ? 0.6 : 1 }}>
          {saving ? "جارٍ الحفظ…" : "حفظ التغييرات"}
        </button>
        <button onClick={onCancel} style={btnGhost}>إلغاء</button>
      </div>
    </div>
  );
}

export default function RadioControlAdminPage() {
  const [stations, setStations] = useState<StationRow[]>([]);
  const [categories, setCategories] = useState<CategoryRow[]>([]);
  const [streamTypes, setStreamTypes] = useState<StreamTypeRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      if (!supabase) throw new Error("Supabase غير مُهيأ في هذه البيئة.");
      const [stRes, catRes, typeRes] = await Promise.all([
        supabase
          .schema("app")
          .from("stations")
          .select("id, name_ar, name_en, stream_url, fallback_stream_url, logo_url, stream_type, station_source, is_active, is_featured, sort_order, health_status, category_id, categories(slug, name_ar)")
          .is("deleted_at", null)
          .order("sort_order", { ascending: true })
          .order("name_ar", { ascending: true }),
        supabase.schema("app").from("categories").select("id, slug, name_ar").eq("is_active", true).order("sort_order"),
        supabase.schema("app").from("stream_types").select("code, description").eq("is_active", true).order("code"),
      ]);
      if (stRes.error) throw new Error(`تعذّرت قراءة المحطات: ${stRes.error.message}`);
      if (catRes.error) throw new Error(`تعذّرت قراءة التصنيفات: ${catRes.error.message}`);
      if (typeRes.error) throw new Error(`تعذّرت قراءة أنواع البث: ${typeRes.error.message}`);
      setStations((stRes.data ?? []) as StationRow[]);
      setCategories((catRes.data ?? []) as CategoryRow[]);
      setStreamTypes((typeRes.data ?? []) as StreamTypeRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر التحميل.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const toggleActive = async (station: StationRow) => {
    if (!supabase) return;
    setBusyId(station.id);
    setMessage(null);
    try {
      const { error: uerr } = await supabase
        .schema("app")
        .from("stations")
        .update({ is_active: !station.is_active })
        .eq("id", station.id);
      if (uerr) throw new Error(uerr.message);
      setStations((prev) => prev.map((s) => (s.id === station.id ? { ...s, is_active: !s.is_active } : s)));
      setMessage(`تم ${!station.is_active ? "تفعيل" : "تعطيل"} «${station.name_ar}» فوريًا.`);
    } catch (e) {
      setError(e instanceof Error ? `تعذّر تبديل الحالة: ${e.message}` : "تعذّر تبديل الحالة.");
    } finally {
      setBusyId(null);
    }
  };

  const handleDelete = async (station: StationRow) => {
    if (!supabase) return;
    if (!window.confirm(`حذف «${station.name_ar}» نهائيًا من الكتالوج؟`)) return;
    setBusyId(station.id);
    try {
      const { error: derr } = await supabase.schema("app").from("stations").delete().eq("id", station.id);
      if (derr) throw new Error(derr.message);
      setStations((prev) => prev.filter((s) => s.id !== station.id));
      setMessage(`تم حذف «${station.name_ar}».`);
    } catch (e) {
      setError(e instanceof Error ? `تعذّر الحذف: ${e.message}` : "تعذّر الحذف.");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>إدارة كتالوج المحطات</h1>
        <button onClick={load} style={{ ...btnGhost, borderColor: "#2E9E9E", color: "#fff", backgroundColor: "#243B6B" }}>
          ⟳ تحديث
        </button>
      </div>
      <p style={{ color: "#2E9E9E", marginBottom: "1.5rem" }}>
        الكتالوج يُدار بالكامل من جدول <code dir="ltr">app.stations</code>: الاسم، رابط البث، الشعار،
        التفعيل/التعطيل الفوري، الترتيب، ونوع البث — وتظهر التغييرات في التطبيق مباشرة.
      </p>

      {message && (
        <div style={{ backgroundColor: "#172235", border: "1px solid #2E9E9E", borderRadius: "8px", padding: "0.75rem 1rem", marginBottom: "1rem", color: "#34D399", fontSize: "0.9rem" }}>
          {message}
        </div>
      )}
      {error && (
        <div style={{ backgroundColor: "#172235", border: "1px solid #B91C1C", borderRadius: "8px", padding: "1rem", marginBottom: "1rem" }}>
          <div style={{ color: "#FCA5A5", fontWeight: 600, marginBottom: "0.5rem" }}>تعذّر التحميل</div>
          <div style={{ color: "#9DAEC6", fontSize: "0.9rem", marginBottom: "1rem" }}>{error}</div>
          <button onClick={load} style={{ backgroundColor: "#B91C1C", color: "#fff", border: "none", borderRadius: "8px", padding: "0.5rem 1.2rem", cursor: "pointer" }}>
            إعادة المحاولة
          </button>
        </div>
      )}

      {loading ? (
        <div style={{ color: "#9DAEC6" }}>جارٍ التحميل من قاعدة البيانات…</div>
      ) : !error && stations.length === 0 ? (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", padding: "3rem", textAlign: "center", color: "#9DAEC6" }}>
          لا توجد محطات مسجلة في <code dir="ltr">app.stations</code> حاليًا.
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
          {stations.map((st) => {
            const busy = busyId === st.id;
            const editing = editingId === st.id;
            return (
              <div key={st.id} style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", padding: "1.25rem" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "1rem", flexWrap: "wrap" }}>
                  <div style={{ display: "flex", gap: "1rem", alignItems: "center" }}>
                    {st.logo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={st.logo_url} alt="" style={{ width: 48, height: 48, borderRadius: "8px", objectFit: "cover", backgroundColor: "#0E1726" }} />
                    ) : (
                      <div style={{ width: 48, height: 48, borderRadius: "8px", backgroundColor: "#0E1726", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "1.4rem" }}>
                        📻
                      </div>
                    )}
                    <div>
                      <div style={{ fontWeight: 700, fontSize: "1.05rem" }}>{st.name_ar}</div>
                      <div style={{ fontSize: "0.8rem", color: "#9DAEC6", marginTop: "0.2rem" }}>
                        <code dir="ltr">{st.stream_type}</code> • {st.station_source} • ترتيب: {st.sort_order}
                        {(() => { const c = categoryOf(st); return c ? ` • ${c.name_ar}` : ""; })()}
                        {st.is_featured ? " • ⭐ مميزة" : ""}
                      </div>
                      <div style={{ fontSize: "0.8rem", color: "#2E9E9E", marginTop: "0.2rem", wordBreak: "break-all" }} dir="ltr">
                        {st.stream_url}
                      </div>
                    </div>
                  </div>
                  <div style={{ display: "flex", gap: "0.5rem", alignItems: "center", flexWrap: "wrap" }}>
                    <button
                      onClick={() => toggleActive(st)}
                      disabled={busy}
                      title={st.is_active ? "تعطيل فوري" : "تفعيل فوري"}
                      style={{
                        backgroundColor: st.is_active ? "#10B981" : "#374151",
                        color: "#fff", border: "none", padding: "0.5rem 1rem", borderRadius: "20px",
                        fontWeight: 600, cursor: busy ? "wait" : "pointer", fontSize: "0.85rem",
                        opacity: busy ? 0.6 : 1,
                      }}
                    >
                      {busy ? "…" : st.is_active ? "مفعّلة ✓" : "معطّلة"}
                    </button>
                    <button onClick={() => setEditingId(editing ? null : st.id)} style={btnGhost}>
                      {editing ? "إغلاق التحرير" : "✏️ تحرير"}
                    </button>
                    <button
                      onClick={() => handleDelete(st)}
                      disabled={busy}
                      style={{ ...btnGhost, color: "#F87171", borderColor: "#7F1D1D" }}
                    >
                      🗑️ حذف
                    </button>
                  </div>
                </div>
                {editing && (
                  <StationEditor
                    station={st}
                    categories={categories}
                    streamTypes={streamTypes}
                    onCancel={() => setEditingId(null)}
                    onSaved={() => {
                      setEditingId(null);
                      load();
                    }}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
