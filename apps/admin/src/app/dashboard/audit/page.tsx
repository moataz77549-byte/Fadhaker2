"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * سجل التدقيق — قراءة حقيقية (للقراءة فقط) من جدول app.audit_logs.
 *
 * الـ schema المعتمد (من migration ‏20260830040900):
 *   id (bigint), actor_id, action, resource_type, resource_id, request_id,
 *   ip_hash, old_values, new_values, metadata, created_at.
 *
 * السجل إلحاقي (append-only): لا تعديل ولا حذف من هذه الصفحة.
 * عند غياب الجدول أو عدم صلاحية القراءة تُعرض حالة صادقة — لا صفوف ثابتة.
 */

interface AuditRow {
  id: number;
  actor_id: string | null;
  action: string;
  resource_type: string;
  resource_id: string | null;
  request_id: string | null;
  created_at: string;
}

const cardStyle: React.CSSProperties = {
  backgroundColor: "#172235",
  padding: "1.5rem",
  borderRadius: "12px",
  border: "1px solid #243B6B",
};

export default function AuditAdminPage() {
  const [logs, setLogs] = useState<AuditRow[]>([]);
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
    const { data, error } = await supabase
      .schema("app")
      .from("audit_logs")
      .select("id,actor_id,action,resource_type,resource_id,request_id,created_at")
      .order("id", { ascending: false })
      .limit(100);
    setLoading(false);
    if (error) {
      setUnavailable(true);
      setLogs([]);
      return;
    }
    setLogs((data ?? []) as AuditRow[]);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>سجل التدقيق والمراقبة الأمنية</h1>
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
          تحديث السجل
        </button>
      </div>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        سجل غير قابل للتعديل (Append-Only) من جدول <code dir="ltr">app.audit_logs</code> — للقراءة فقط، دون كشف أي أسرار
      </p>

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل سجل التدقيق…</div>}

      {!loading && unavailable && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🔒</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>سجل التدقيق غير متاح</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدول <code dir="ltr">app.audit_logs</code> غير موجود في هذه البيئة أو لا صلاحية قراءة لعميل الإدارة
            (مقيد بمفتاح الخدمة service-role حسب سياسات RLS) — راجع مالك قاعدة البيانات.
          </div>
        </div>
      )}

      {!loading && !unavailable && logs.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد أحداث تدقيق مسجلة</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            ستظهر هنا الأحداث فور تسجيلها عبر دالة التدقيق.
          </div>
        </div>
      )}

      {!loading && !unavailable && logs.length > 0 && (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflow: "hidden" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>#</th>
                <th style={{ padding: "1rem" }}>الإجراء (Action)</th>
                <th style={{ padding: "1rem" }}>المورد المستهدف</th>
                <th style={{ padding: "1rem" }}>الفاعل</th>
                <th style={{ padding: "1rem" }}>معرّف الطلب (Request ID)</th>
                <th style={{ padding: "1rem" }}>التوقيت</th>
              </tr>
            </thead>
            <tbody>
              {logs.map((log) => (
                <tr key={log.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#9DAEC6" }}>{log.id}</td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#60A5FA" }} dir="ltr">{log.action}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }} dir="ltr">
                    {log.resource_type}{log.resource_id ? `:${log.resource_id}` : ""}
                  </td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#9DAEC6", fontSize: "0.85rem" }} dir="ltr">
                    {log.actor_id ? log.actor_id.slice(0, 8) : "—"}
                  </td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#9DAEC6", fontSize: "0.85rem" }} dir="ltr">
                    {log.request_id ? log.request_id.slice(0, 8) : "—"}
                  </td>
                  <td style={{ padding: "1rem", color: "#9DAEC6", fontSize: "0.85rem" }} dir="ltr">
                    {new Date(log.created_at).toLocaleString("en-GB")}
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
