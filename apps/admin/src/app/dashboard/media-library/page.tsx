"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type MediaStatus = "UPLOADING" | "PROCESSING" | "READY" | "FAILED" | "ARCHIVED";

interface MediaRow {
  id: string;
  title: string;
  description: string | null;
  duration_ms: number | null;
  format: string | null;
  bitrate_kbps: number | null;
  file_size_bytes: number;
  sha256: string | null;
  status: MediaStatus;
  failure_message: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  reciters: { name_ar: string | null }[] | null;
}

function reciterName(row: MediaRow): string {
  const r = row.reciters;
  if (Array.isArray(r) && r.length > 0) return r[0]?.name_ar ?? "—";
  return "—";
}

const STATUS_LABEL: Record<MediaStatus, string> = {
  UPLOADING: "جارٍ الرفع",
  PROCESSING: "قيد المعالجة",
  READY: "جاهز",
  FAILED: "فشل",
  ARCHIVED: "مؤرشف",
};

const STATUS_COLOR: Record<MediaStatus, string> = {
  UPLOADING: "#60A5FA",
  PROCESSING: "#FBBF24",
  READY: "#34D399",
  FAILED: "#F87171",
  ARCHIVED: "#9DAEC6",
};

function formatDuration(ms: number | null): string {
  if (ms == null || ms <= 0) return "—";
  const totalSeconds = Math.round(ms / 1000);
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
  return `${h > 0 ? `${h}:` : ""}${mm}:${String(s).padStart(2, "0")}`;
}

function formatSize(bytes: number): string {
  if (bytes >= 1_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`;
  if (bytes >= 1_000) return `${(bytes / 1_000).toFixed(1)} KB`;
  return `${bytes} B`;
}

function shortSha(sha: string | null): string {
  if (!sha) return "—";
  return sha.length > 12 ? `${sha.slice(0, 6)}…${sha.slice(-4)}` : sha;
}

export default function MediaLibraryAdminPage() {
  const [rows, setRows] = useState<MediaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      if (!supabase) throw new Error("Supabase غير مُهيأ في هذه البيئة — لا يمكن عرض المكتبة.");
      const { data, error: qerr } = await supabase
        .schema("app")
        .from("media")
        .select(
          "id, title, description, duration_ms, format, bitrate_kbps, file_size_bytes, sha256, status, failure_message, metadata, created_at, reciters(name_ar)"
        )
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(100);
      if (qerr) throw new Error(`تعذّرت قراءة جدول app.media: ${qerr.message}`);
      setRows((data ?? []) as MediaRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل المكتبة.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.5rem" }}>
        <div>
          <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>مكتبة الصوت والمعالجة</h1>
          <p style={{ color: "#2E9E9E", marginTop: "0.2rem" }}>
            بيانات حية من جدول <code dir="ltr">app.media</code> — حالات المعالجة الفعلية دون بيانات تجريبية
          </p>
        </div>
        <button
          onClick={() => { load(); setNotice(true); }}
          style={{ backgroundColor: "#243B6B", color: "#fff", border: "1px solid #2E9E9E", padding: "0.75rem 1.5rem", borderRadius: "8px", fontWeight: 600, cursor: "pointer" }}
        >
          ⟳ تحديث
        </button>
      </div>

      {notice && (
        <div style={{ backgroundColor: "#172235", border: "1px solid #243B6B", borderRadius: "8px", padding: "1rem", marginBottom: "1.5rem", color: "#9DAEC6", fontSize: "0.9rem" }}>
          رفع الملفات الجديدة يتم عبر مسار التخزين/المعالجة (Storage + معالج الصوت) خارج هذه الشاشة؛ هذه الصفحة للعرض ومتابعة حالة المعالجة فقط.
        </div>
      )}

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
          لا توجد ملفات صوتية مسجلة في <code dir="ltr">app.media</code> حاليًا.
        </div>
      ) : (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right", minWidth: "900px" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>العنوان</th>
                <th style={{ padding: "1rem" }}>القارئ</th>
                <th style={{ padding: "1rem" }}>المدة</th>
                <th style={{ padding: "1rem" }}>الحجم</th>
                <th style={{ padding: "1rem" }}>بصمة SHA-256</th>
                <th style={{ padding: "1rem" }}>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((m) => (
                <tr key={m.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontWeight: 600 }}>
                    {m.title}
                    {m.status === "FAILED" && m.failure_message && (
                      <div style={{ fontWeight: 400, fontSize: "0.8rem", color: "#F87171", marginTop: "0.25rem" }}>
                        {m.failure_message}
                      </div>
                    )}
                  </td>
                  <td style={{ padding: "1rem" }}>{reciterName(m)}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }}>{formatDuration(m.duration_ms)}</td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }}>{formatSize(m.file_size_bytes)}</td>
                  <td style={{ padding: "1rem", fontFamily: "monospace", color: "#9DAEC6", fontSize: "0.85rem" }}>
                    {shortSha(m.sha256)}
                  </td>
                  <td style={{ padding: "1rem", color: STATUS_COLOR[m.status], fontWeight: 600 }}>
                    {STATUS_LABEL[m.status] ?? m.status}
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
