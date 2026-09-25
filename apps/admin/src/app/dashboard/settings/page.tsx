"use client";

import React, { useCallback, useEffect, useState } from "react";
import { fetchConfigRow, saveConfigRow, type ConfigValueType } from "@/lib/appConfig";

interface SectionDef {
  key: string;
  title: string;
  description: string;
  valueType: ConfigValueType;
  isPublic: boolean;
  configDescription: string;
  placeholder: string;
}

const SECTIONS: SectionDef[] = [
  {
    key: "feature_flags",
    title: "مفاتيح الميزات (feature_flags)",
    description: "تفعيل أو تعطيل التبويبات والمميزات عن بُعد في تطبيقات المستخدمين — تُحفظ فعليًا في app.app_config",
    valueType: "JSON",
    isPublic: true,
    configDescription: "Remote feature flags consumed by mobile clients",
    placeholder: '{\n  "radio_enabled": true,\n  "offline_downloads": true\n}',
  },
  {
    key: "min_supported_version",
    title: "أدنى إصدار مدعوم (min_supported_version)",
    description: "التحكم في متطلبات التحديث الإجباري للتطبيقات — تُحفظ فعليًا في app.app_config",
    valueType: "JSON",
    isPublic: true,
    configDescription: "Minimum supported app versions; clients force-update below these",
    placeholder: '{\n  "android": "1.0.64",\n  "ios": "1.0.64",\n  "force_update": false\n}',
  },
  {
    key: "maintenance",
    title: "وضع الصيانة (maintenance)",
    description: "إظهار شاشة صيانة عامة مع رسالة توجيهية للمستخدمين — تُحفظ فعليًا في app.app_config",
    valueType: "JSON",
    isPublic: true,
    configDescription: "Global maintenance mode flag and message",
    placeholder: '{\n  "is_active": false,\n  "message_ar": "صيانة مجدولة وجيزة"\n}',
  },
];

const cardStyle: React.CSSProperties = {
  backgroundColor: "#172235",
  padding: "1.5rem",
  borderRadius: "12px",
  border: "1px solid #243B6B",
};

function ConfigSection({ def }: { def: SectionDef }) {
  const [text, setText] = useState(def.placeholder);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const [exists, setExists] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const row = await fetchConfigRow(def.key);
      if (row) {
        setText(JSON.stringify(row.value, null, 2));
        setExists(true);
      } else {
        setExists(false);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّرت قراءة الإعداد.");
    } finally {
      setLoading(false);
    }
  }, [def.key]);

  useEffect(() => {
    load();
  }, [load]);

  const handleSave = async () => {
    setError(null);
    setSavedAt(null);
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      setError("صيغة JSON غير صالحة. يرجى تصحيح الخطأ قبل الحفظ — لم يُحفظ شيء.");
      return;
    }
    setSaving(true);
    try {
      await saveConfigRow({
        key: def.key,
        value: parsed,
        valueType: def.valueType,
        isPublic: def.isPublic,
        description: def.configDescription,
      });
      setExists(true);
      setSavedAt(new Date().toLocaleString("ar"));
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر حفظ الإعداد.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={cardStyle}>
      <h3 style={{ fontSize: "1.1rem", fontWeight: 600, marginBottom: "0.5rem" }}>
        {def.title}{" "}
        <span style={{ fontSize: "0.75rem", color: exists ? "#34D399" : "#9DAEC6", fontWeight: 400 }}>
          {loading ? "" : exists ? "● محفوظ في قاعدة البيانات" : "○ غير موجود بعد — سيُنشأ عند الحفظ"}
        </span>
      </h3>
      <p style={{ fontSize: "0.85rem", color: "#9DAEC6", marginBottom: "1rem" }}>{def.description}</p>
      {loading ? (
        <div style={{ color: "#9DAEC6" }}>جارٍ التحميل من قاعدة البيانات…</div>
      ) : (
        <>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={6}
            dir="ltr"
            style={{
              width: "100%", padding: "0.75rem", borderRadius: "6px", backgroundColor: "#0E1726",
              border: "1px solid #243B6B", color: "#60A5FA", fontFamily: "monospace", fontSize: "0.85rem",
              textAlign: "left",
            }}
          />
          {error && (
            <div style={{ color: "#FCA5A5", fontSize: "0.85rem", marginTop: "0.75rem" }}>⚠️ {error}</div>
          )}
          {savedAt && (
            <div style={{ color: "#34D399", fontSize: "0.85rem", marginTop: "0.75rem" }}>
              ✓ تم الحفظ فعليًا في قاعدة البيانات — {savedAt}
            </div>
          )}
          <div style={{ display: "flex", gap: "0.75rem", marginTop: "1rem" }}>
            <button
              onClick={handleSave}
              disabled={saving}
              style={{
                backgroundColor: saving ? "#374151" : "#2E9E9E", color: "#fff", border: "none",
                padding: "0.6rem 1.2rem", borderRadius: "6px", fontWeight: 600,
                cursor: saving ? "wait" : "pointer",
              }}
            >
              {saving ? "جارٍ الحفظ…" : "حفظ التغييرات"}
            </button>
            <button
              onClick={load}
              disabled={loading}
              style={{
                backgroundColor: "transparent", color: "#9DAEC6", border: "1px solid #243B6B",
                padding: "0.6rem 1.2rem", borderRadius: "6px", cursor: "pointer",
              }}
            >
              إعادة التحميل
            </button>
          </div>
        </>
      )}
    </div>
  );
}

export default function SettingsAdminPage() {
  return (
    <div style={{ maxWidth: "900px" }}>
      <h1 style={{ fontSize: "1.8rem", fontWeight: 700, marginBottom: "0.5rem" }}>الإعدادات وتهيئة التشغيل (Runtime Config)</h1>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        تُقرأ القيم الحالية من جدول <code dir="ltr">app.app_config</code> وتُحفظ فيه فعليًا — لا توجد رسائل نجاح وهمية.
      </p>
      <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
        {SECTIONS.map((def) => (
          <ConfigSection key={def.key} def={def} />
        ))}
      </div>
    </div>
  );
}
