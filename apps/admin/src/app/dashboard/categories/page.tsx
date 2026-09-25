"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * إدارة التصنيفات — CRUD حقيقي على جدول app.categories.
 *
 * الـ schema المعتمد (من migration ‏20260830040900):
 *   id, parent_id, slug (unique), name_ar, name_en, description, icon_key,
 *   icon, is_active, is_system, sort_order, created_at, updated_at, deleted_at.
 *
 * - تصنيفات النظام (is_system) محمية من الحذف العرضي.
 * - عند غياب الجدول في بيئة لم تُطبَّق فيها migrations تُعرض حالة
 *   غير متاح صادقة — لا بيانات ثابتة.
 */

interface CategoryRow {
  id: string;
  slug: string;
  name_ar: string;
  name_en: string | null;
  description: string | null;
  icon_key: string | null;
  is_active: boolean;
  is_system: boolean;
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

const emptyForm = {
  slug: "",
  name_ar: "",
  name_en: "",
  description: "",
  icon_key: "",
  is_active: true,
  sort_order: 0,
};

export default function CategoriesAdminPage() {
  const [categories, setCategories] = useState<CategoryRow[]>([]);
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
      .from("categories")
      .select("id,slug,name_ar,name_en,description,icon_key,is_active,is_system,sort_order")
      .is("deleted_at", null)
      .order("sort_order", { ascending: true })
      .order("name_ar", { ascending: true });
    setLoading(false);
    if (error) {
      setTableMissing(true);
      setCategories([]);
      return;
    }
    setCategories((data ?? []) as CategoryRow[]);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const validate = (): string | null => {
    if (!SLUG_PATTERN.test(form.slug.trim()))
      return "المعرّف (slug) يجب أن يكون حروفًا إنجليزية صغيرة وأرقامًا وشرطات فقط (مثال: haramain).";
    if (!form.name_ar.trim()) return "اسم التصنيف بالعربية مطلوب.";
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
      description: form.description.trim() || null,
      icon_key: form.icon_key.trim() || null,
      is_active: form.is_active,
      sort_order: Number.isFinite(form.sort_order) ? form.sort_order : 0,
    };
    try {
      if (editingId) {
        const { error } = await supabase.schema("app").from("categories").update(payload).eq("id", editingId);
        if (error) throw error;
      } else {
        const { error } = await supabase.schema("app").from("categories").insert(payload);
        if (error) throw error;
      }
      setForm(emptyForm);
      setEditingId(null);
      setMsg({ ok: true, text: editingId ? "حُفظت التعديلات." : "أُضيف التصنيف." });
      load();
    } catch (e) {
      setMsg({ ok: false, text: `تعذّر الحفظ: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = (c: CategoryRow) => {
    setEditingId(c.id);
    setForm({
      slug: c.slug,
      name_ar: c.name_ar,
      name_en: c.name_en ?? "",
      description: c.description ?? "",
      icon_key: c.icon_key ?? "",
      is_active: c.is_active,
      sort_order: c.sort_order,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const handleDelete = async (c: CategoryRow) => {
    if (!supabase) return;
    if (c.is_system) {
      setMsg({ ok: false, text: "تصنيف نظام أساسي محمي — لا يمكن حذفه." });
      return;
    }
    if (!confirm(`حذف تصنيف «${c.name_ar}» نهائيًا؟`)) return;
    const { error } = await supabase.schema("app").from("categories").delete().eq("id", c.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر الحذف: ${error.message}` });
      return;
    }
    setMsg({ ok: true, text: "حُذف التصنيف." });
    load();
  };

  const toggleActive = async (c: CategoryRow) => {
    if (!supabase) return;
    const { error } = await supabase
      .schema("app")
      .from("categories")
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
    <div>
      <h1 style={{ fontSize: "1.8rem", fontWeight: 700, marginBottom: "0.5rem" }}>التصنيفات والمقامات</h1>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        إدارة تصنيفات التلاوات من جدول <code dir="ltr">app.categories</code> — تصنيفات النظام الأساسية محمية من الحذف العرضي
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
          {editingId ? "تعديل تصنيف" : "إضافة تصنيف جديد"}
        </h2>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المعرّف (slug) *</label>
            <input
              type="text"
              value={form.slug}
              onChange={(e) => set({ slug: e.target.value })}
              placeholder="haramain"
              style={inputStyle}
              dir="ltr"
            />
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اسم التصنيف (عربي) *</label>
            <input
              type="text"
              value={form.name_ar}
              onChange={(e) => set({ name_ar: e.target.value })}
              placeholder="تلاوات الحرمين الشريفين"
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
              placeholder="Haramain Recitations"
              style={inputStyle}
              dir="ltr"
            />
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>مفتاح الأيقونة (اختياري)</label>
            <input
              type="text"
              value={form.icon_key}
              onChange={(e) => set({ icon_key: e.target.value })}
              placeholder="mosque"
              style={inputStyle}
              dir="ltr"
            />
          </div>
        </div>
        <div style={{ marginBottom: "1rem" }}>
          <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>الوصف (اختياري)</label>
          <input
            type="text"
            value={form.description}
            onChange={(e) => set({ description: e.target.value })}
            placeholder="وصف مختصر للتصنيف"
            style={inputStyle}
          />
        </div>
        <div style={{ display: "flex", gap: "1.5rem", alignItems: "center", marginBottom: "1.25rem", flexWrap: "wrap" }}>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input type="checkbox" checked={form.is_active} onChange={(e) => set({ is_active: e.target.checked })} />
            تصنيف مفعّل
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
            {saving ? "جارٍ الحفظ…" : editingId ? "حفظ التعديلات" : "إضافة التصنيف"}
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
        <h2 style={{ fontSize: "1.3rem", fontWeight: 700 }}>التصنيفات الحالية</h2>
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

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل التصنيفات…</div>}

      {!loading && tableMissing && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🏷️</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>جدول التصنيفات غير متاح</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدول <code dir="ltr">app.categories</code> غير موجود في هذه البيئة أو لا صلاحية قراءة —
            طبّق الـ migration الخاص به من مالك قاعدة البيانات ثم أعد التحميل.
          </div>
        </div>
      )}

      {!loading && !tableMissing && categories.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد تصنيفات بعد</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            أضف أول تصنيف من النموذج أعلاه.
          </div>
        </div>
      )}

      {!loading && !tableMissing && categories.length > 0 && (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflow: "hidden" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>اسم التصنيف</th>
                <th style={{ padding: "1rem" }}>المعرّف (Slug)</th>
                <th style={{ padding: "1rem" }}>الوصف</th>
                <th style={{ padding: "1rem" }}>الحالة</th>
                <th style={{ padding: "1rem" }}>النوع</th>
                <th style={{ padding: "1rem" }}>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {categories.map((c) => (
                <tr key={c.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontWeight: 600 }}>{c.name_ar}</td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#2E9E9E" }} dir="ltr">{c.slug}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }}>{c.description ?? "—"}</td>
                  <td style={{ padding: "1rem" }}>
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
                      {c.is_active ? "مفعّل" : "معطّل"}
                    </span>
                  </td>
                  <td style={{ padding: "1rem" }}>
                    <span style={{
                      padding: "0.25rem 0.6rem",
                      borderRadius: "6px",
                      backgroundColor: c.is_system ? "#243B6B" : "#374151",
                      fontSize: "0.8rem",
                      color: c.is_system ? "#60A5FA" : "#D1D5DB"
                    }}>
                      {c.is_system ? "🔒 نظام أساسي محمي" : "مخصص"}
                    </span>
                  </td>
                  <td style={{ padding: "1rem" }}>
                    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
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
                        disabled={c.is_system}
                        title={c.is_system ? "تصنيف نظام أساسي محمي — لا يمكن حذفه" : "حذف التصنيف"}
                        style={{
                          backgroundColor: "transparent",
                          color: c.is_system ? "#6B7280" : "#F87171",
                          border: `1px solid ${c.is_system ? "#374151" : "#7F1D1D"}`,
                          padding: "0.35rem 0.8rem",
                          borderRadius: "6px",
                          cursor: c.is_system ? "not-allowed" : "pointer",
                          fontSize: "0.8rem",
                        }}
                      >
                        حذف
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
