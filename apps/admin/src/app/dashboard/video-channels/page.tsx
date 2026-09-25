"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * إدارة القنوات المرئية — CRUD حقيقي على جدول app.video_channels.
 *
 * الـ schema المعتمد (موثّق في docs/VIDEO_CHANNELS.md ومن migration ‏20260830040700):
 *   slug, name_ar, name_en, stream_url, logo_url, is_active, sort_order.
 * نوع المصدر يُشتق في التطبيق من الرابط (.m3u8 → HLS، روابط يوتيوب → YouTube، .mp4 → MP4)
 * — لا توجد أعمدة منفصلة لكل نوع.
 *
 * - كل العمليات عبر عميل الإدارة (anon + JWT المدير)؛ لا مفاتيح سرّية في المتصفح.
 * - عند غياب الجدول في بيئة لم تُطبَّق فيها migrations تُعرض حالة فارغة صادقة.
 */

interface ChannelRow {
  id: string;
  slug: string;
  name_ar: string;
  name_en: string | null;
  stream_url: string;
  logo_url: string | null;
  is_active: boolean;
  sort_order: number;
}

const cardStyle: React.CSSProperties = {
  backgroundColor: "#172235",
  padding: "1.5rem",
  borderRadius: "12px",
  border: "1px solid #243B6B",
};

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "0.75rem",
  borderRadius: "6px",
  backgroundColor: "#0E1726",
  border: "1px solid #243B6B",
  color: "#F8F6F1",
};

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function streamKindLabel(url: string): string {
  const u = url.toLowerCase();
  if (u.includes(".m3u8")) return "HLS";
  if (u.includes("youtube.com") || u.includes("youtu.be")) return "YouTube";
  if (u.includes(".mp4")) return "MP4";
  return "رابط";
}

const emptyForm = { slug: "", name_ar: "", name_en: "", stream_url: "", logo_url: "", is_active: true, sort_order: 0 };

export default function VideoChannelsPage() {
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tableMissing, setTableMissing] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setTableMissing(false);
    if (!supabase) {
      setLoading(false);
      setTableMissing(true);
      return;
    }
    const { data, error } = await supabase
      .schema("app")
      .from("video_channels")
      .select("id,slug,name_ar,name_en,stream_url,logo_url,is_active,sort_order")
      .order("sort_order", { ascending: true })
      .order("name_ar", { ascending: true });
    setLoading(false);
    if (error) {
      setTableMissing(true);
      setChannels([]);
      return;
    }
    setChannels((data ?? []) as ChannelRow[]);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const validate = (): string | null => {
    if (!SLUG_PATTERN.test(form.slug.trim()))
      return "المعرّف (slug) يجب أن يكون حروفًا إنجليزية صغيرة وأرقامًا وشرطات فقط (مثال: quran-tv).";
    if (!form.name_ar.trim()) return "اسم القناة بالعربية مطلوب.";
    const url = form.stream_url.trim();
    if (!url) return "رابط البث مطلوب.";
    if (!/^https?:\/\//i.test(url)) return "رابط البث يجب أن يبدأ بـ http:// أو https://.";
    return null;
  };

  const handleSave = async () => {
    setMsg(null);
    const err = validate();
    if (err) {
      setMsg({ ok: false, text: err });
      return;
    }
    if (!supabase) {
      setMsg({ ok: false, text: "إعدادات Supabase غير مكتملة في بيئة الإدارة." });
      return;
    }
    setSaving(true);
    const payload = {
      slug: form.slug.trim(),
      name_ar: form.name_ar.trim(),
      name_en: form.name_en.trim() || null,
      stream_url: form.stream_url.trim(),
      logo_url: form.logo_url.trim() || null,
      is_active: form.is_active,
      sort_order: Number.isFinite(form.sort_order) ? form.sort_order : 0,
    };
    try {
      if (editingId) {
        const { error } = await supabase.schema("app").from("video_channels").update(payload).eq("id", editingId);
        if (error) throw error;
      } else {
        const { error } = await supabase.schema("app").from("video_channels").insert(payload);
        if (error) throw error;
      }
      setForm(emptyForm);
      setEditingId(null);
      setMsg({ ok: true, text: editingId ? "حُفظت التعديلات." : "أُضيفت القناة." });
      load();
    } catch (e) {
      setMsg({ ok: false, text: `تعذّر الحفظ: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = (c: ChannelRow) => {
    setEditingId(c.id);
    setForm({
      slug: c.slug,
      name_ar: c.name_ar,
      name_en: c.name_en ?? "",
      stream_url: c.stream_url,
      logo_url: c.logo_url ?? "",
      is_active: c.is_active,
      sort_order: c.sort_order,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const handleDelete = async (c: ChannelRow) => {
    if (!supabase) return;
    if (!confirm(`حذف قناة «${c.name_ar}» نهائيًا؟`)) return;
    const { error } = await supabase.schema("app").from("video_channels").delete().eq("id", c.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر الحذف: ${error.message}` });
      return;
    }
    setMsg({ ok: true, text: "حُذفت القناة." });
    load();
  };

  const toggleActive = async (c: ChannelRow) => {
    if (!supabase) return;
    const { error } = await supabase
      .schema("app")
      .from("video_channels")
      .update({ is_active: !c.is_active })
      .eq("id", c.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر التحديث: ${error.message}` });
      return;
    }
    load();
  };

  const set = (patch: Partial<typeof emptyForm>) => setForm((f) => ({ ...f, ...patch }));

  return (
    <div style={{ maxWidth: "1000px" }}>
      <h1 style={{ fontSize: "1.8rem", fontWeight: 700, marginBottom: "0.5rem" }}>القنوات المرئية</h1>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        تُقرأ القنوات المفعّلة في التطبيق فورًا (نوع المصدر يُشتق من الرابط: .m3u8 → HLS، روابط يوتيوب → YouTube، .mp4 → MP4)
      </p>

      {msg && (
        <div
          style={{
            backgroundColor: msg.ok ? "#064E3B" : "#7F1D1D",
            color: msg.ok ? "#6EE7B7" : "#FCA5A5",
            padding: "1rem",
            borderRadius: "8px",
            marginBottom: "1.5rem",
            lineHeight: 1.8,
          }}
        >
          {msg.text}
        </div>
      )}

      <div style={{ ...cardStyle, marginBottom: "2rem" }}>
        <h2 style={{ fontSize: "1.15rem", fontWeight: 700, marginBottom: "1.25rem" }}>
          {editingId ? "تعديل قناة" : "إضافة قناة جديدة"}
        </h2>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المعرّف (slug) *</label>
            <input
              type="text"
              value={form.slug}
              onChange={(e) => set({ slug: e.target.value })}
              placeholder="quran-tv"
              style={inputStyle}
              dir="ltr"
            />
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اسم القناة (عربي) *</label>
            <input
              type="text"
              value={form.name_ar}
              onChange={(e) => set({ name_ar: e.target.value })}
              placeholder="قناة القرآن الكريم"
              style={inputStyle}
            />
          </div>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>الاسم (إنجليزي — اختياري)</label>
            <input
              type="text"
              value={form.name_en}
              onChange={(e) => set({ name_en: e.target.value })}
              placeholder="Quran TV"
              style={inputStyle}
              dir="ltr"
            />
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الشعار (اختياري)</label>
            <input
              type="text"
              value={form.logo_url}
              onChange={(e) => set({ logo_url: e.target.value })}
              placeholder="https://…/logo.png"
              style={inputStyle}
              dir="ltr"
            />
          </div>
        </div>
        <div style={{ marginBottom: "1rem" }}>
          <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط البث *</label>
          <input
            type="text"
            value={form.stream_url}
            onChange={(e) => set({ stream_url: e.target.value })}
            placeholder="https://…/stream.m3u8 أو رابط يوتيوب أو .mp4"
            style={inputStyle}
            dir="ltr"
          />
          {form.stream_url.trim() && (
            <div style={{ fontSize: "0.8rem", color: "#2E9E9E", marginTop: "0.4rem" }}>
              النوع المشتق من الرابط: {streamKindLabel(form.stream_url)}
            </div>
          )}
        </div>
        <div style={{ display: "flex", gap: "1.5rem", alignItems: "center", marginBottom: "1.25rem", flexWrap: "wrap" }}>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input type="checkbox" checked={form.is_active} onChange={(e) => set({ is_active: e.target.checked })} />
            قناة مفعّلة
          </label>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
            ترتيب العرض
            <input
              type="number"
              value={form.sort_order}
              onChange={(e) => set({ sort_order: parseInt(e.target.value, 10) || 0 })}
              style={{ ...inputStyle, width: "90px", padding: "0.5rem" }}
              dir="ltr"
            />
          </label>
        </div>
        <div style={{ display: "flex", gap: "0.75rem" }}>
          <button
            onClick={handleSave}
            disabled={saving}
            style={{
              backgroundColor: saving ? "#374151" : "#2E9E9E",
              color: "#fff",
              border: "none",
              padding: "0.75rem 1.6rem",
              borderRadius: "8px",
              fontWeight: 700,
              cursor: saving ? "wait" : "pointer",
            }}
          >
            {saving ? "جارٍ الحفظ…" : editingId ? "حفظ التعديلات" : "إضافة القناة"}
          </button>
          {editingId && (
            <button
              onClick={() => {
                setEditingId(null);
                setForm(emptyForm);
                setMsg(null);
              }}
              style={{
                backgroundColor: "transparent",
                color: "#9DAEC6",
                border: "1px solid #243B6B",
                padding: "0.75rem 1.6rem",
                borderRadius: "8px",
                cursor: "pointer",
              }}
            >
              إلغاء التعديل
            </button>
          )}
        </div>
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h2 style={{ fontSize: "1.3rem", fontWeight: 700 }}>القنوات الحالية</h2>
        <button
          onClick={load}
          style={{
            backgroundColor: "transparent",
            color: "#9DAEC6",
            border: "1px solid #243B6B",
            padding: "0.5rem 1rem",
            borderRadius: "6px",
            cursor: "pointer",
            fontSize: "0.85rem",
          }}
        >
          تحديث القائمة
        </button>
      </div>

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل القنوات…</div>}

      {!loading && tableMissing && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🎬</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>جدول القنوات المرئية غير متاح</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدول <code dir="ltr">app.video_channels</code> غير موجود في هذه البيئة أو لا صلاحية قراءة —
            طبّق الـ migration الخاص به من مالك قاعدة البيانات ثم أعد التحميل.
          </div>
        </div>
      )}

      {!loading && !tableMissing && channels.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد قنوات مرئية بعد</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            أضف أول قناة من النموذج أعلاه لتظهر في قسم الفيديو داخل التطبيق.
          </div>
        </div>
      )}

      {!loading && !tableMissing && channels.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          {channels.map((c) => (
            <div key={c.id} style={{ ...cardStyle, padding: "1rem 1.25rem" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "1rem" }}>
                <div style={{ flex: 1, display: "flex", gap: "0.9rem", alignItems: "center" }}>
                  {c.logo_url ? (
                    <img
                      src={c.logo_url}
                      alt=""
                      style={{ width: "48px", height: "48px", borderRadius: "8px", objectFit: "cover", flexShrink: 0 }}
                    />
                  ) : (
                    <div
                      style={{
                        width: "48px",
                        height: "48px",
                        borderRadius: "8px",
                        backgroundColor: "#243B6B",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontSize: "1.4rem",
                        flexShrink: 0,
                      }}
                    >
                      🎬
                    </div>
                  )}
                  <div>
                    <div style={{ fontWeight: 600, color: "#F8F6F1" }}>{c.name_ar}</div>
                    <div style={{ fontSize: "0.8rem", color: "#9DAEC6", marginTop: "0.2rem" }} dir="ltr">
                      {c.slug} • {streamKindLabel(c.stream_url)}
                    </div>
                  </div>
                </div>
                <div style={{ display: "flex", gap: "0.5rem", flexShrink: 0, alignItems: "center" }}>
                  <span
                    style={{
                      fontSize: "0.75rem",
                      fontWeight: 600,
                      padding: "0.25rem 0.75rem",
                      borderRadius: "999px",
                      backgroundColor: c.is_active ? "#064E3B" : "#374151",
                      color: c.is_active ? "#6EE7B7" : "#9DAEC6",
                    }}
                  >
                    {c.is_active ? "مفعّلة" : "معطّلة"}
                  </span>
                  <button
                    onClick={() => toggleActive(c)}
                    style={{ backgroundColor: "transparent", color: "#2E9E9E", border: "1px solid #2E9E9E", padding: "0.35rem 0.8rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem" }}
                  >
                    {c.is_active ? "تعطيل" : "تفعيل"}
                  </button>
                  <button
                    onClick={() => handleEdit(c)}
                    style={{ backgroundColor: "transparent", color: "#9DAEC6", border: "1px solid #243B6B", padding: "0.35rem 0.8rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem" }}
                  >
                    تعديل
                  </button>
                  <button
                    onClick={() => handleDelete(c)}
                    style={{ backgroundColor: "transparent", color: "#F87171", border: "1px solid #7F1D1D", padding: "0.35rem 0.8rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem" }}
                  >
                    حذف
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
