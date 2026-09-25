"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * صفحة الأجهزة — قراءة حقيقية من جدول app.installations.
 *
 * الـ schema المعتمد (من migration ‏20260830040900):
 *   id, installation_secret_hash, platform ('android','ios','web'), app_version,
 *   build_number, locale, timezone, notifications_enabled,
 *   firebase_token_encrypted, consent_version, consented_at, last_seen_at,
 *   revoked_at, created_at, updated_at.
 *
 * - تُقرأ الأعمدة التشغيلية فقط (platform, app_version, build_number, locale,
 *   timezone, notifications_enabled, last_seen_at, created_at, revoked_at) —
 *   لا تُطلب أعمدة الأسرار (installation_secret_hash, firebase_token_encrypted) أبدًا.
 * - الجدول مقيد بمفتاح الخدمة (service-role) حسب سياسات RLS، فعند رفض القراءة
 *   تُعرض حالة صادقة بدل صفوف تجريبية.
 */

interface InstallationRow {
  id: string;
  platform: string;
  app_version: string;
  build_number: number;
  locale: string;
  timezone: string;
  notifications_enabled: boolean;
  last_seen_at: string;
  created_at: string;
  revoked_at: string | null;
}

const cardStyle: React.CSSProperties = {
  backgroundColor: "#172235",
  padding: "1.5rem",
  borderRadius: "12px",
  border: "1px solid #243B6B",
};

export default function DevicesAdminPage() {
  const [installations, setInstallations] = useState<InstallationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [unavailable, setUnavailable] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setUnavailable(false);
    if (!supabase) {
      setLoading(false);
      setUnavailable(true);
      return;
    }
    // أعمدة تشغيلية فقط — لا أسرار ولا توكنز FCM.
    const { data, error } = await supabase
      .schema("app")
      .from("installations")
      .select("id,platform,app_version,build_number,locale,timezone,notifications_enabled,last_seen_at,created_at,revoked_at")
      .order("last_seen_at", { ascending: false })
      .limit(100);
    setLoading(false);
    if (error) {
      setUnavailable(true);
      setInstallations([]);
      return;
    }
    setInstallations((data ?? []) as InstallationRow[]);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>الأجهزة النشطة والتثبيتات</h1>
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
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        بيانات الأجهزة المستعارة المجهولة دون تتبع الهويات الشخصية (Zero Surveillance) — من جدول <code dir="ltr">app.installations</code>
      </p>

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل بيانات الأجهزة…</div>}

      {!loading && unavailable && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "3rem 2rem" }}>
          <div style={{ fontSize: "2.5rem", marginBottom: "1rem" }}>📱</div>
          <div style={{ fontSize: "1.1rem", fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>
            لا توجد بيانات أجهزة متاحة للعرض
          </div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8, maxWidth: "520px", margin: "0 auto" }}>
            سجلات التثبيتات محمية ولا تُكشف إلا عبر مفتاح الخدمة (service-role) حسب سياسات RLS —
            جدول <code dir="ltr">app.installations</code> غير مقروء من عميل الإدارة الحالي.
            ستظهر الأجهزة هنا بعد منح صلاحية قراءة مصرّح بها.
          </div>
        </div>
      )}

      {!loading && !unavailable && installations.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "3rem 2rem" }}>
          <div style={{ fontSize: "2.5rem", marginBottom: "1rem" }}>📱</div>
          <div style={{ fontSize: "1.1rem", fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>
            لا توجد تثبيتات مسجلة بعد
          </div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8, maxWidth: "520px", margin: "0 auto" }}>
            ستظهر التثبيتات هنا فور تسجيل أول جهاز من تطبيق الجوال.
          </div>
        </div>
      )}

      {!loading && !unavailable && installations.length > 0 && (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflow: "hidden" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>المنصة</th>
                <th style={{ padding: "1rem" }}>نسخة التطبيق</th>
                <th style={{ padding: "1rem" }}>اللغة</th>
                <th style={{ padding: "1rem" }}>الإشعارات</th>
                <th style={{ padding: "1rem" }}>آخر ظهور</th>
                <th style={{ padding: "1rem" }}>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {installations.map((d) => (
                <tr key={d.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontWeight: 600 }} dir="ltr">{d.platform}</td>
                  <td style={{ padding: "1rem", fontFamily: "monospace" }} dir="ltr">{d.app_version}+{d.build_number}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }} dir="ltr">{d.locale}</td>
                  <td style={{ padding: "1rem" }}>
                    <span
                      style={{
                        fontSize: "0.75rem",
                        fontWeight: 600,
                        padding: "0.25rem 0.75rem",
                        borderRadius: "999px",
                        backgroundColor: d.notifications_enabled ? "#064E3B" : "#374151",
                        color: d.notifications_enabled ? "#6EE7B7" : "#9DAEC6",
                      }}
                    >
                      {d.notifications_enabled ? "مفعّلة" : "معطّلة"}
                    </span>
                  </td>
                  <td style={{ padding: "1rem", color: "#9DAEC6", fontSize: "0.85rem" }} dir="ltr">
                    {new Date(d.last_seen_at).toLocaleString("en-GB")}
                  </td>
                  <td style={{ padding: "1rem" }}>
                    <span
                      style={{
                        fontSize: "0.75rem",
                        fontWeight: 600,
                        padding: "0.25rem 0.75rem",
                        borderRadius: "999px",
                        backgroundColor: d.revoked_at ? "#7F1D1D" : "#064E3B",
                        color: d.revoked_at ? "#FCA5A5" : "#6EE7B7",
                      }}
                    >
                      {d.revoked_at ? "مُسحوب" : "نشط"}
                    </span>
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
