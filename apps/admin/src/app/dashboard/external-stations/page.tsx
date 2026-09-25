"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface ExternalStationRow {
  id: string;
  name_ar: string;
  name_en: string | null;
  stream_url: string;
  fallback_stream_url: string | null;
  stream_type: string;
  logo_url: string | null;
  is_active: boolean;
  health_status: string;
  rights_status: string;
  attribution_text: string | null;
}

export default function ExternalStationsAdminPage() {
  const [rows, setRows] = useState<ExternalStationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      if (!supabase) throw new Error("Supabase غير مُهيأ في هذه البيئة — لا يمكن عرض المحطات.");
      const { data, error: qerr } = await supabase
        .schema("app")
        .from("stations")
        .select(
          "id, name_ar, name_en, stream_url, fallback_stream_url, stream_type, logo_url, is_active, health_status, rights_status, attribution_text"
        )
        .eq("station_source", "EXTERNAL")
        .is("deleted_at", null)
        .order("sort_order", { ascending: true })
        .order("name_ar", { ascending: true });
      if (qerr) throw new Error(`تعذّرت قراءة جدول app.stations: ${qerr.message}`);
      setRows((data ?? []) as ExternalStationRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل المحطات.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>المحطات الإذاعية الخارجية (Virtual / External)</h1>
        <button
          onClick={load}
          style={{ backgroundColor: "#243B6B", color: "#fff", border: "1px solid #2E9E9E", padding: "0.6rem 1.2rem", borderRadius: "8px", fontWeight: 600, cursor: "pointer" }}
        >
          ⟳ تحديث
        </button>
      </div>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        بيانات حية من جدول <code dir="ltr">app.stations</code> حيث <code dir="ltr">station_source = 'EXTERNAL'</code> —
        تُشغَّل مباشرة عبر رابط المصدر ومفصولة عن محرك البث الداخلي
      </p>

      {error && (
        <div style={{ backgroundColor: "#172235", border: "1px solid #B91C1C", borderRadius: "8px", padding: "1rem", marginBottom: "1.5rem" }}>
          <div style={{ color: "#FCA5A5", fontWeight: 600, marginBottom: "0.5rem" }}>تعذّر التحميل</div>
          <div style={{ color: "#9DAEC6", fontSize: "0.9rem", marginBottom: "1rem" }}>{error}</div>
          <button onClick={load} style={{ backgroundColor: "#B91C1C", color: "#fff", border: "none", borderRadius: "8px", padding: "0.5rem 1.2rem", cursor: "pointer" }}>
            إعادة المحاولة
          </button>
        </div>
      )}

      {loading ? (
        <div style={{ color: "#9DAEC6" }}>جارٍ التحميل من قاعدة البيانات…</div>
      ) : !error && rows.length === 0 ? (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", padding: "3rem", textAlign: "center", color: "#9DAEC6" }}>
          لا توجد محطات خارجية مسجلة في <code dir="ltr">app.stations</code> حاليًا.
        </div>
      ) : (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right", minWidth: "900px" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>اسم المحطة</th>
                <th style={{ padding: "1rem" }}>رابط البث (Source URL)</th>
                <th style={{ padding: "1rem" }}>نوع البث</th>
                <th style={{ padding: "1rem" }}>الحقوق</th>
                <th style={{ padding: "1rem" }}>الحالة الصحية</th>
                <th style={{ padding: "1rem" }}>مفعّلة</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((st) => (
                <tr key={st.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontWeight: 600 }}>
                    {st.name_ar}
                    {st.attribution_text && (
                      <div style={{ fontWeight: 400, fontSize: "0.8rem", color: "#9DAEC6", marginTop: "0.25rem" }}>
                        {st.attribution_text}
                      </div>
                    )}
                  </td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#2E9E9E", fontSize: "0.85rem", wordBreak: "break-all" }}>
                    {st.stream_url}
                  </td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }}><code dir="ltr">{st.stream_type}</code></td>
                  <td style={{ padding: "1rem", color: "#C77955", fontSize: "0.85rem" }}>{st.rights_status}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6", fontSize: "0.85rem" }}>{st.health_status}</td>
                  <td style={{ padding: "1rem", color: st.is_active ? "#34D399" : "#9DAEC6", fontWeight: 600 }}>
                    {st.is_active ? "مفعّلة" : "معطّلة"}
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
