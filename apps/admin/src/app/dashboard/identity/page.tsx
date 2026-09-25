"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { BrandMark } from "@/components/BrandMark";

/**
 * هوية المنصة — قراءة الصف الوحيد (id=1) من جدول app.identity_settings
 * والحفظ عبر upsert.
 *
 * الـ schema المعتمد (من migration ‏20260830041500):
 *   id smallint pk (دائمًا 1), site_name, tagline_ar, tagline_en, logo_url,
 *   logo_dark_url, favicon_url, primary_color, accent_color, support_url,
 *   privacy_url, terms_url, contact_email, metadata, created_at, updated_at.
 *
 * الجدول مقيد بمفتاح الخدمة (service-role) حسب سياسات RLS —
 * عند رفض الوصول تُعرض حالة صادقة.
 */

interface IdentityRow {
  id: number;
  site_name: string;
  tagline_ar: string;
  tagline_en: string;
  logo_url: string | null;
  logo_dark_url: string | null;
  favicon_url: string | null;
  primary_color: string;
  accent_color: string;
  support_url: string | null;
  privacy_url: string | null;
  terms_url: string | null;
  contact_email: string | null;
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

const HEX_PATTERN = /^#[0-9a-fA-F]{6}$/;

const emptyForm = {
  site_name: "",
  tagline_ar: "",
  tagline_en: "",
  logo_url: "",
  logo_dark_url: "",
  favicon_url: "",
  primary_color: "#243B6B",
  accent_color: "#2E9E9E",
  support_url: "",
  privacy_url: "",
  terms_url: "",
  contact_email: "",
};

export default function IdentityAdminPage() {
  const [row, setRow] = useState<IdentityRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setUnavailable(false);
    if (!supabase) {
      setLoading(false);
      setUnavailable(true);
      return;
    }
    const { data, error } = await supabase
      .schema("app")
      .from("identity_settings")
      .select("*")
      .eq("id", 1)
      .maybeSingle();
    setLoading(false);
    if (error) {
      setUnavailable(true);
      setRow(null);
      return;
    }
    const typed = (data ?? null) as IdentityRow | null;
    setRow(typed);
    setForm({
      site_name: typed?.site_name ?? "",
      tagline_ar: typed?.tagline_ar ?? "",
      tagline_en: typed?.tagline_en ?? "",
      logo_url: typed?.logo_url ?? "",
      logo_dark_url: typed?.logo_dark_url ?? "",
      favicon_url: typed?.favicon_url ?? "",
      primary_color: typed?.primary_color ?? "#243B6B",
      accent_color: typed?.accent_color ?? "#2E9E9E",
      support_url: typed?.support_url ?? "",
      privacy_url: typed?.privacy_url ?? "",
      terms_url: typed?.terms_url ?? "",
      contact_email: typed?.contact_email ?? "",
    });
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const validate = (): string | null => {
    if (!form.site_name.trim()) return "اسم المنصة مطلوب.";
    if (!form.tagline_ar.trim()) return "السطر التعريفي بالعربية مطلوب.";
    if (!HEX_PATTERN.test(form.primary_color.trim()))
      return "اللون الرئيسي يجب أن يكون بصيغة hex مثل #243B6B.";
    if (!HEX_PATTERN.test(form.accent_color.trim()))
      return "لون التمييز يجب أن يكون بصيغة hex مثل #2E9E9E.";
    if (form.contact_email.trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.contact_email.trim()))
      return "البريد الإلكتروني للتواصل غير صالح.";
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
      id: 1,
      site_name: form.site_name.trim(),
      tagline_ar: form.tagline_ar.trim(),
      tagline_en: form.tagline_en.trim(),
      logo_url: form.logo_url.trim() || null,
      logo_dark_url: form.logo_dark_url.trim() || null,
      favicon_url: form.favicon_url.trim() || null,
      primary_color: form.primary_color.trim(),
      accent_color: form.accent_color.trim(),
      support_url: form.support_url.trim() || null,
      privacy_url: form.privacy_url.trim() || null,
      terms_url: form.terms_url.trim() || null,
      contact_email: form.contact_email.trim() || null,
    };
    try {
      const { error } = await supabase.schema("app").from("identity_settings").upsert(payload, { onConflict: "id" });
      if (error) throw error;
      setMsg({ ok: true, text: "حُفظت هوية المنصة." });
      load();
    } catch (e) {
      setMsg({ ok: false, text: `تعذّر الحفظ: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const set = (patch: Partial<typeof emptyForm>) => setForm((f) => ({ ...f, ...patch }));

  const previewName = loading ? "…" : row?.site_name ?? form.site_name;
  const previewTagline = loading ? "…" : row?.tagline_ar ?? form.tagline_ar;
  const previewPrimary = row?.primary_color ?? form.primary_color;
  const previewAccent = row?.accent_color ?? form.accent_color;
  const previewLogo = row?.logo_url ?? form.logo_url;

  return (
    <div style={{ maxWidth: "900px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>هوية منصة «فذكر»</h1>
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
          تحديث البيانات
        </button>
      </div>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        الهوية البصرية من جدول <code dir="ltr">app.identity_settings</code> (صف واحد — id=1)
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

      {loading && <div style={{ color: "#9DAEC6", marginBottom: "2rem" }}>جارٍ تحميل هوية المنصة…</div>}

      {!loading && unavailable && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem", marginBottom: "2rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🔒</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>هوية المنصة غير متاحة</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدول <code dir="ltr">app.identity_settings</code> غير موجود في هذه البيئة أو لا صلاحية قراءة لعميل الإدارة
            (مقيد بمفتاح الخدمة service-role حسب سياسات RLS) — راجع مالك قاعدة البيانات.
          </div>
        </div>
      )}

      {!loading && !unavailable && (
        <>
          <div style={{ backgroundColor: "#172235", padding: "2rem", borderRadius: "16px", border: "1px solid #243B6B", textAlign: "center", marginBottom: "2rem" }}>
            <div style={{ display: "flex", justifyContent: "center", marginBottom: "1rem" }}>
              {previewLogo ? (
                <img src={previewLogo} alt="" style={{ width: "84px", height: "84px", objectFit: "contain", borderRadius: "16px" }} />
              ) : (
                <BrandMark size={84} />
              )}
            </div>
            <h2 style={{ fontSize: "1.8rem", fontWeight: 800, margin: "0 0 0.5rem 0", color: "#F8F6F1" }}>{previewName}</h2>
            <div style={{ color: previewAccent, fontWeight: 600, fontSize: "1rem", marginBottom: "1rem" }}>{previewTagline}</div>
            <div style={{ display: "flex", justifyContent: "center", gap: "0.75rem", flexWrap: "wrap" }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: "0.4rem", fontSize: "0.85rem", color: "#9DAEC6" }}>
                <span style={{ width: "18px", height: "18px", borderRadius: "4px", backgroundColor: previewPrimary, display: "inline-block" }} />
                <code dir="ltr">{previewPrimary}</code>
              </span>
              <span style={{ display: "inline-flex", alignItems: "center", gap: "0.4rem", fontSize: "0.85rem", color: "#9DAEC6" }}>
                <span style={{ width: "18px", height: "18px", borderRadius: "4px", backgroundColor: previewAccent, display: "inline-block" }} />
                <code dir="ltr">{previewAccent}</code>
              </span>
            </div>
          </div>

          <div style={{ ...cardStyle, marginBottom: "2rem" }}>
            <h2 style={{ fontSize: "1.15rem", fontWeight: 700, marginBottom: "1.25rem" }}>تعديل الهوية</h2>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اسم المنصة *</label>
                <input type="text" value={form.site_name} onChange={(e) => set({ site_name: e.target.value })} placeholder="فذكر" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>السطر التعريفي (عربي) *</label>
                <input type="text" value={form.tagline_ar} onChange={(e) => set({ tagline_ar: e.target.value })} placeholder="منصة القرآن الكريم والبث الإذاعي" style={inputStyle} />
              </div>
            </div>
            <div style={{ marginBottom: "1rem" }}>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>السطر التعريفي (إنجليزي)</label>
              <input type="text" value={form.tagline_en} onChange={(e) => set({ tagline_en: e.target.value })} placeholder="Quran Platform & Radio Broadcast" style={inputStyle} dir="ltr" />
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الشعار</label>
                <input type="text" value={form.logo_url} onChange={(e) => set({ logo_url: e.target.value })} placeholder="https://…/logo.png" style={inputStyle} dir="ltr" />
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الشعار (الوضع الداكن)</label>
                <input type="text" value={form.logo_dark_url} onChange={(e) => set({ logo_dark_url: e.target.value })} placeholder="https://…/logo-dark.png" style={inputStyle} dir="ltr" />
              </div>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الأيقونة (favicon)</label>
                <input type="text" value={form.favicon_url} onChange={(e) => set({ favicon_url: e.target.value })} placeholder="https://…/favicon.ico" style={inputStyle} dir="ltr" />
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>البريد الإلكتروني للتواصل</label>
                <input type="text" value={form.contact_email} onChange={(e) => set({ contact_email: e.target.value })} placeholder="support@example.com" style={inputStyle} dir="ltr" />
              </div>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اللون الرئيسي *</label>
                <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
                  <input type="color" value={HEX_PATTERN.test(form.primary_color) ? form.primary_color : "#243B6B"} onChange={(e) => set({ primary_color: e.target.value })} style={{ width: "48px", height: "42px", padding: 0, border: "1px solid #243B6B", borderRadius: "6px", backgroundColor: "#0E1726", cursor: "pointer" }} />
                  <input type="text" value={form.primary_color} onChange={(e) => set({ primary_color: e.target.value })} style={{ ...inputStyle, flex: 1 }} dir="ltr" />
                </div>
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>لون التمييز *</label>
                <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
                  <input type="color" value={HEX_PATTERN.test(form.accent_color) ? form.accent_color : "#2E9E9E"} onChange={(e) => set({ accent_color: e.target.value })} style={{ width: "48px", height: "42px", padding: 0, border: "1px solid #243B6B", borderRadius: "6px", backgroundColor: "#0E1726", cursor: "pointer" }} />
                  <input type="text" value={form.accent_color} onChange={(e) => set({ accent_color: e.target.value })} style={{ ...inputStyle, flex: 1 }} dir="ltr" />
                </div>
              </div>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "1rem", marginBottom: "1.25rem" }}>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الدعم</label>
                <input type="text" value={form.support_url} onChange={(e) => set({ support_url: e.target.value })} placeholder="https://…" style={inputStyle} dir="ltr" />
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط سياسة الخصوصية</label>
                <input type="text" value={form.privacy_url} onChange={(e) => set({ privacy_url: e.target.value })} placeholder="https://…" style={inputStyle} dir="ltr" />
              </div>
              <div>
                <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>رابط الشروط والأحكام</label>
                <input type="text" value={form.terms_url} onChange={(e) => set({ terms_url: e.target.value })} placeholder="https://…" style={inputStyle} dir="ltr" />
              </div>
            </div>
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
              {saving ? "جارٍ الحفظ…" : "حفظ الهوية"}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
