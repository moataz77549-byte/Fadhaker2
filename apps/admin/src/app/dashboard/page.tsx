"use client";

import React, { useCallback, useEffect, useState } from "react";
import { BrandMark } from "@/components/BrandMark";
import { fetchDashboardStats, type DashboardStats } from "@/lib/dashboardStats";

type LoadState =
  | { kind: "loading" }
  | { kind: "error"; message: string }
  | { kind: "ready"; stats: DashboardStats };

const cardStyle: React.CSSProperties = {
  backgroundColor: "#172235",
  padding: "1.5rem",
  borderRadius: "12px",
  border: "1px solid #243B6B",
};

function MetricCard(props: { label: string; value: number | null; hint: string; loading: boolean }) {
  const { label, value, hint, loading } = props;
  return (
    <div style={cardStyle}>
      <span style={{ fontSize: "0.85rem", color: "#9DAEC6" }}>{label}</span>
      <div style={{ fontSize: "2rem", fontWeight: 700, color: "#F8F6F1", marginTop: "0.5rem" }}>
        {loading ? "…" : value === null ? "—" : value.toLocaleString("ar-EG")}
      </div>
      <span style={{ fontSize: "0.8rem", color: "#2E9E9E" }}>
        {loading ? "جارٍ التحميل…" : value === null ? "لا توجد بيانات متاحة" : hint}
      </span>
    </div>
  );
}

function EmptyLine({ text }: { text: string }) {
  return <div style={{ color: "#9DAEC6" }}>{text}</div>;
}

export default function DashboardOverviewPage() {
  const [state, setState] = useState<LoadState>({ kind: "loading" });

  const load = useCallback(async () => {
    setState({ kind: "loading" });
    try {
      const stats = await fetchDashboardStats();
      setState({ kind: "ready", stats });
    } catch (error) {
      setState({
        kind: "error",
        message: error instanceof Error ? error.message : "تعذّر تحميل إحصائيات لوحة التحكم.",
      });
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const loading = state.kind === "loading";
  const stats: DashboardStats | null = state.kind === "ready" ? state.stats : null;

  return (
    <div>
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "2rem" }}>
        <div>
          <h1 style={{ fontSize: "1.8rem", fontWeight: 700 }}>لوحة التحكم والمتابعة</h1>
          <p style={{ color: "#2E9E9E", fontSize: "0.95rem", marginTop: "0.2rem" }}>
            حالة المنظومة — «فذكر»
          </p>
        </div>
        <button
          onClick={load}
          style={{
            backgroundColor: "#243B6B",
            color: "#F8F6F1",
            border: "1px solid #2E9E9E",
            borderRadius: "8px",
            padding: "0.5rem 1rem",
            cursor: "pointer",
            fontSize: "0.85rem",
          }}
        >
          تحديث البيانات
        </button>
      </div>

      {state.kind === "error" && (
        <div style={{ ...cardStyle, borderColor: "#B91C1C", marginBottom: "1.5rem" }}>
          <div style={{ color: "#FCA5A5", fontWeight: 600, marginBottom: "0.5rem" }}>تعذّر تحميل البيانات</div>
          <div style={{ color: "#9DAEC6", fontSize: "0.9rem", marginBottom: "1rem" }}>{state.message}</div>
          <button
            onClick={load}
            style={{
              backgroundColor: "#B91C1C",
              color: "#fff",
              border: "none",
              borderRadius: "8px",
              padding: "0.5rem 1.2rem",
              cursor: "pointer",
            }}
          >
            إعادة المحاولة
          </button>
        </div>
      )}

      {stats && !stats.configured && (
        <div style={{ ...cardStyle, borderColor: "#C77955", marginBottom: "1.5rem" }}>
          <div style={{ color: "#C77955", fontWeight: 600 }}>
            لم يتم تهيئة الاتصال بـ Supabase في هذه البيئة — تُعرض حالات فارغة بدل الأرقام.
          </div>
        </div>
      )}

      {/* Metrics Grid — بيانات فعلية من Supabase */}
      <div style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
        gap: "1.2rem",
        marginBottom: "2rem"
      }}>
        <MetricCard label="الإذاعات النشطة" value={stats?.stations ?? null} hint="محطات مفعّلة في قاعدة البيانات" loading={loading} />
        <MetricCard label="القراء المعتمدون" value={stats?.reciters ?? null} hint="قراء مسجلون في قاعدة البيانات" loading={loading} />
        <MetricCard label="التلاوات الجاهزة" value={stats?.mediaReady ?? null} hint="ملفات صوتية بحالة READY" loading={loading} />
        <MetricCard label="المستمعون النشطون الآن" value={stats?.listeners ?? null} hint="آخر قراءة من مقاييس البث" loading={loading} />
        <MetricCard label="الأجهزة المسجلة" value={stats?.users ?? null} hint="تثبيتات غير ملغاة (لا حسابات في التطبيق)" loading={loading} />
        <MetricCard label="مهام المعالجة النشطة" value={stats?.processingJobs ?? null} hint="مهام صوت قيد الرفع أو المعالجة" loading={loading} />
        <MetricCard label="حملات الإشعارات" value={stats?.campaigns ?? null} hint="حملات مسجلة في قاعدة البيانات" loading={loading} />
        <MetricCard label="قنوات الفيديو النشطة" value={stats?.videoChannels ?? null} hint="قنوات مفعّلة في app.video_channels" loading={loading} />
      </div>

      {/* Live panels */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1.5rem" }}>
        <div style={cardStyle}>
          <div style={{ display: "flex", alignItems: "center", gap: "0.75rem", marginBottom: "1rem" }}>
            <BrandMark size={32} isRadio={true} />
            <h3 style={{ fontSize: "1.1rem", fontWeight: 600 }}>البث الحالي</h3>
          </div>
          {loading ? (
            <EmptyLine text="جارٍ التحميل…" />
          ) : stats?.nowPlaying ? (
            <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.7 }}>
              <div><strong>المسار الحالي:</strong> {stats.nowPlaying.title ?? "—"}{stats.nowPlaying.artist ? ` — ${stats.nowPlaying.artist}` : ""}</div>
              <div><strong>المسار التالي:</strong> {stats.nowPlaying.nextTitle ?? "—"}</div>
              {stats.nowPlaying.updatedAt && (
                <div style={{ fontSize: "0.8rem", marginTop: "0.5rem" }}>
                  آخر تحديث: {new Date(stats.nowPlaying.updatedAt).toLocaleString("ar")}
                </div>
              )}
            </div>
          ) : (
            <EmptyLine text="لا توجد بيانات بث حية مرتبطة حاليًا." />
          )}
        </div>

        <div style={cardStyle}>
          <h3 style={{ fontSize: "1.1rem", fontWeight: 600, marginBottom: "1rem" }}>
            حالة خدمات المعالجة
          </h3>
          {loading ? (
            <EmptyLine text="جارٍ التحميل…" />
          ) : stats?.worker ? (
            <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.7 }}>
              <div><strong>الخدمة:</strong> {stats.worker.service}</div>
              <div><strong>الحالة:</strong> {stats.worker.status}</div>
              {stats.worker.lastSeenAt && (
                <div><strong>آخر نبضة:</strong> {new Date(stats.worker.lastSeenAt).toLocaleString("ar")}</div>
              )}
            </div>
          ) : (
            <EmptyLine text="لا توجد نبضات خدمات مسجلة حاليًا." />
          )}
        </div>
      </div>
    </div>
  );
}
