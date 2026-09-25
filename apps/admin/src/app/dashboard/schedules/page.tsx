"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * إدارة الجداول الزمنية — CRUD حقيقي على جدول app.schedules.
 *
 * الـ schema المعتمد (من migration ‏20260830040900):
 *   id, station_id (إلزامي → app.stations), name, content_type
 *   ('MEDIA','PLAYLIST','PROGRAM'), media_id, playlist_id, program_id,
 *   schedule_type ('ONE_TIME','DAILY','WEEKLY'), start_date, end_date,
 *   start_time, days_of_week smallint[], timezone, priority
 *   ('LOW','NORMAL','HIGH','EMERGENCY','LIVE'), interrupt_policy
 *   ('FINISH_CURRENT','INTERRUPT','PLAY_NEXT'), enabled, next_run_at,
 *   version, created_by, created_at, updated_at, deleted_at.
 *
 * عند غياب الجدول تُعرض حالة غير متاح صادقة — لا بيانات ثابتة.
 */

interface ScheduleRow {
  id: string;
  station_id: string;
  name: string;
  content_type: string;
  media_id: string | null;
  playlist_id: string | null;
  program_id: string | null;
  schedule_type: string;
  start_date: string;
  end_date: string | null;
  start_time: string;
  days_of_week: number[] | null;
  timezone: string;
  priority: string;
  enabled: boolean;
  next_run_at: string | null;
  stations: { name_ar: string } | null;
}

interface StationOption {
  id: string;
  name_ar: string;
}

interface TargetOption {
  id: string;
  name: string;
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

const CONTENT_TYPES = [
  { value: "MEDIA", label: "مادة صوتية" },
  { value: "PLAYLIST", label: "قائمة تشغيل" },
  { value: "PROGRAM", label: "برنامج" },
];

const SCHEDULE_TYPES = [
  { value: "ONE_TIME", label: "مرة واحدة" },
  { value: "DAILY", label: "يومي" },
  { value: "WEEKLY", label: "أسبوعي" },
];

const PRIORITIES = ["LOW", "NORMAL", "HIGH", "EMERGENCY", "LIVE"];

const DAYS = [
  { value: 0, label: "الأحد" },
  { value: 1, label: "الاثنين" },
  { value: 2, label: "الثلاثاء" },
  { value: 3, label: "الأربعاء" },
  { value: 4, label: "الخميس" },
  { value: 5, label: "الجمعة" },
  { value: 6, label: "السبت" },
];

function contentTypeLabel(v: string): string {
  return CONTENT_TYPES.find((t) => t.value === v)?.label ?? v;
}

function scheduleTypeLabel(v: string): string {
  return SCHEDULE_TYPES.find((t) => t.value === v)?.label ?? v;
}

function daysLabel(days: number[] | null): string {
  if (!days || days.length === 0) return "—";
  return days
    .slice()
    .sort((a, b) => a - b)
    .map((d) => DAYS.find((x) => x.value === d)?.label ?? d)
    .join("، ");
}

const emptyForm = {
  station_id: "",
  name: "",
  content_type: "PLAYLIST",
  target_id: "",
  schedule_type: "DAILY",
  start_date: "",
  end_date: "",
  start_time: "",
  days_of_week: [] as number[],
  timezone: "Asia/Riyadh",
  priority: "NORMAL",
  enabled: true,
};

export default function SchedulesAdminPage() {
  const [schedules, setSchedules] = useState<ScheduleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tableMissing, setTableMissing] = useState(false);
  const [stations, setStations] = useState<StationOption[]>([]);
  const [playlists, setPlaylists] = useState<TargetOption[]>([]);
  const [media, setMedia] = useState<TargetOption[]>([]);
  const [programs, setPrograms] = useState<TargetOption[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setTableMissing(false);
    const client = supabase;
    if (!client) {
      setLoading(false);
      setTableMissing(true);
      return;
    }
    const [stationRes, playlistRes, mediaRes, programRes, schedRes] = await Promise.all([
      client.schema("app").from("stations").select("id,name_ar").eq("is_active", true).is("deleted_at", null).order("name_ar"),
      client.schema("app").from("playlists").select("id,name").eq("is_active", true).is("deleted_at", null).order("name").limit(100),
      client.schema("app").from("media").select("id,title").eq("status", "READY").is("deleted_at", null).order("title").limit(50),
      client.schema("app").from("programs").select("id,name").eq("is_active", true).is("deleted_at", null).order("name").limit(100),
      client
        .schema("app")
        .from("schedules")
        .select("id,station_id,name,content_type,media_id,playlist_id,program_id,schedule_type,start_date,end_date,start_time,days_of_week,timezone,priority,enabled,next_run_at,stations(name_ar)")
        .is("deleted_at", null)
        .order("start_date", { ascending: true })
        .order("start_time", { ascending: true }),
    ]);
    setStations((stationRes.data ?? []) as StationOption[]);
    setPlaylists(((playlistRes.data ?? []) as { id: string; name: string }[]).map((p) => ({ id: p.id, name: p.name })));
    setMedia(((mediaRes.data ?? []) as { id: string; title: string }[]).map((m) => ({ id: m.id, name: m.title })));
    setPrograms(((programRes.data ?? []) as { id: string; name: string }[]).map((p) => ({ id: p.id, name: p.name })));
    setLoading(false);
    if (schedRes.error) {
      setTableMissing(true);
      setSchedules([]);
      return;
    }
    const normalized = ((((schedRes.data ?? []) as unknown) as Array<Record<string, unknown>>).map((r) => ({
      ...(r as object),
      stations: Array.isArray(r.stations) ? (r.stations[0] as { name_ar: string } | undefined) ?? null : (r.stations as { name_ar: string } | null),
    }))) as ScheduleRow[];
    setSchedules(normalized);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const toggleDay = (day: number) => {
    setForm((f) => ({
      ...f,
      days_of_week: f.days_of_week.includes(day)
        ? f.days_of_week.filter((d) => d !== day)
        : [...f.days_of_week, day],
    }));
  };

  const validate = (): string | null => {
    if (!form.station_id) return "اختر المحطة المستهدفة.";
    if (!form.name.trim()) return "اسم الجدول مطلوب.";
    if (!form.start_date) return "تاريخ البدء مطلوب.";
    if (!form.start_time) return "وقت البدء مطلوب.";
    if (form.schedule_type === "WEEKLY" && form.days_of_week.length === 0)
      return "اختر يومًا واحدًا على الأقل للجدول الأسبوعي.";
    if (!form.target_id) return "اختر المحتوى المستهدف (مادة/قائمة/برنامج).";
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
    const payload: Record<string, unknown> = {
      station_id: form.station_id,
      name: form.name.trim(),
      content_type: form.content_type,
      schedule_type: form.schedule_type,
      start_date: form.start_date,
      end_date: form.end_date || null,
      start_time: form.start_time,
      days_of_week: form.days_of_week.length > 0 ? form.days_of_week : null,
      timezone: form.timezone.trim() || "Asia/Riyadh",
      priority: form.priority,
      enabled: form.enabled,
      media_id: form.content_type === "MEDIA" ? form.target_id : null,
      playlist_id: form.content_type === "PLAYLIST" ? form.target_id : null,
      program_id: form.content_type === "PROGRAM" ? form.target_id : null,
    };
    try {
      const { error } = await supabase.schema("app").from("schedules").insert(payload);
      if (error) throw error;
      setForm(emptyForm);
      setShowForm(false);
      setMsg({ ok: true, text: "أُضيف الجدول الزمني." });
      load();
    } catch (e) {
      setMsg({ ok: false, text: `تعذّر الحفظ: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (s: ScheduleRow) => {
    if (!supabase) return;
    if (!confirm(`حذف جدول «${s.name}» نهائيًا؟`)) return;
    const { error } = await supabase.schema("app").from("schedules").delete().eq("id", s.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر الحذف: ${error.message}` });
      return;
    }
    setMsg({ ok: true, text: "حُذف الجدول." });
    load();
  };

  const toggleEnabled = async (s: ScheduleRow) => {
    if (!supabase) return;
    const { error } = await supabase.schema("app").from("schedules").update({ enabled: !s.enabled }).eq("id", s.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر التحديث: ${error.message}` });
      return;
    }
    load();
  };

  const set = (patch: Partial<typeof emptyForm>) => setForm((f) => ({ ...f, ...patch }));

  const targetOptions: TargetOption[] =
    form.content_type === "MEDIA" ? media : form.content_type === "PROGRAM" ? programs : playlists;

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.5rem" }}>
        <div>
          <h1 style={{ fontSize: "1.8rem", fontWeight: 700, margin: 0 }}>الجداول الزمنية وأتمتة البث</h1>
          <p style={{ color: "#2E9E9E", marginTop: "0.2rem" }}>
            جدولة تشغيل التلاوات والمحطات من جدول <code dir="ltr">app.schedules</code>
          </p>
        </div>
        <button
          onClick={() => setShowForm((v) => !v)}
          style={{ backgroundColor: "#2E9E9E", color: "#fff", border: "none", padding: "0.75rem 1.5rem", borderRadius: "8px", fontWeight: 600, cursor: "pointer" }}
        >
          {showForm ? "✕ إغلاق النموذج" : "➕ إضافة جدول زمني"}
        </button>
      </div>

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

      {showForm && (
        <div style={{ ...cardStyle, marginBottom: "2rem" }}>
          <h2 style={{ fontSize: "1.15rem", fontWeight: 700, marginBottom: "1.25rem" }}>جدول زمني جديد</h2>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المحطة المستهدفة *</label>
              <select value={form.station_id} onChange={(e) => set({ station_id: e.target.value })} style={inputStyle}>
                <option value="">اختر المحطة…</option>
                {stations.map((s) => (
                  <option key={s.id} value={s.id}>{s.name_ar}</option>
                ))}
              </select>
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اسم الجدول / الحدث *</label>
              <input
                type="text"
                value={form.name}
                onChange={(e) => set({ name: e.target.value })}
                placeholder="جدول فجر الجمعة"
                style={inputStyle}
              />
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>نوع المحتوى</label>
              <select value={form.content_type} onChange={(e) => set({ content_type: e.target.value, target_id: "" })} style={inputStyle}>
                {CONTENT_TYPES.map((t) => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المحتوى المستهدف *</label>
              <select value={form.target_id} onChange={(e) => set({ target_id: e.target.value })} style={inputStyle}>
                <option value="">اختر…</option>
                {targetOptions.map((t) => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>التكرار</label>
              <select value={form.schedule_type} onChange={(e) => set({ schedule_type: e.target.value })} style={inputStyle}>
                {SCHEDULE_TYPES.map((t) => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>تاريخ البدء *</label>
              <input type="date" value={form.start_date} onChange={(e) => set({ start_date: e.target.value })} style={inputStyle} />
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>وقت البدء *</label>
              <input type="time" value={form.start_time} onChange={(e) => set({ start_time: e.target.value })} style={inputStyle} dir="ltr" />
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>تاريخ الانتهاء (اختياري)</label>
              <input type="date" value={form.end_date} onChange={(e) => set({ end_date: e.target.value })} style={inputStyle} />
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المنطقة الزمنية</label>
              <input
                type="text"
                value={form.timezone}
                onChange={(e) => set({ timezone: e.target.value })}
                placeholder="Asia/Riyadh"
                style={inputStyle}
                dir="ltr"
              />
            </div>
            <div>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>الأولوية</label>
              <select value={form.priority} onChange={(e) => set({ priority: e.target.value })} style={inputStyle}>
                {PRIORITIES.map((p) => (
                  <option key={p} value={p}>{p}</option>
                ))}
              </select>
            </div>
          </div>
          {form.schedule_type === "WEEKLY" && (
            <div style={{ marginBottom: "1rem" }}>
              <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>أيام الأسبوع *</label>
              <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
                {DAYS.map((d) => (
                  <label
                    key={d.value}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: "0.4rem",
                      padding: "0.4rem 0.8rem",
                      borderRadius: "6px",
                      border: "1px solid #243B6B",
                      backgroundColor: form.days_of_week.includes(d.value) ? "#243B6B" : "#0E1726",
                      cursor: "pointer",
                      fontSize: "0.85rem",
                    }}
                  >
                    <input
                      type="checkbox"
                      checked={form.days_of_week.includes(d.value)}
                      onChange={() => toggleDay(d.value)}
                    />
                    {d.label}
                  </label>
                ))}
              </div>
            </div>
          )}
          <div style={{ display: "flex", gap: "1.5rem", alignItems: "center", marginBottom: "1.25rem" }}>
            <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
              <input type="checkbox" checked={form.enabled} onChange={(e) => set({ enabled: e.target.checked })} />
              جدول مفعّل
            </label>
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
            {saving ? "جارٍ الحفظ…" : "إضافة الجدول"}
          </button>
        </div>
      )}

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل الجداول الزمنية…</div>}

      {!loading && tableMissing && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🗓️</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>جدول الجداول الزمنية غير متاح</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدول <code dir="ltr">app.schedules</code> غير موجود في هذه البيئة أو لا صلاحية قراءة —
            طبّق الـ migration الخاص به من مالك قاعدة البيانات ثم أعد التحميل.
          </div>
        </div>
      )}

      {!loading && !tableMissing && schedules.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد جداول زمنية بعد</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            أضف أول جدول من زر «إضافة جدول زمني» أعلاه.
          </div>
        </div>
      )}

      {!loading && !tableMissing && schedules.length > 0 && (
        <div style={{ backgroundColor: "#172235", borderRadius: "12px", border: "1px solid #243B6B", overflow: "hidden" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "right" }}>
            <thead>
              <tr style={{ backgroundColor: "#0E1726", borderBottom: "1px solid #243B6B" }}>
                <th style={{ padding: "1rem" }}>اسم الجدول / الحدث</th>
                <th style={{ padding: "1rem" }}>المحطة المستهدفة</th>
                <th style={{ padding: "1rem" }}>النوع والتكرار</th>
                <th style={{ padding: "1rem" }}>الموعد المجدول</th>
                <th style={{ padding: "1rem" }}>المنطقة الزمنية</th>
                <th style={{ padding: "1rem" }}>الحالة</th>
                <th style={{ padding: "1rem" }}>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {schedules.map((s) => (
                <tr key={s.id} style={{ borderBottom: "1px solid #243B6B" }}>
                  <td style={{ padding: "1rem", fontWeight: 600 }}>{s.name}</td>
                  <td style={{ padding: "1rem" }}>{s.stations?.name_ar ?? "—"}</td>
                  <td style={{ padding: "1rem", color: "#C77955" }}>
                    {contentTypeLabel(s.content_type)} • {scheduleTypeLabel(s.schedule_type)}
                  </td>
                  <td style={{ padding: "1rem" }} dir="ltr">
                    {s.start_date} {s.start_time.slice(0, 5)}
                    {s.schedule_type === "WEEKLY" && (
                      <div style={{ fontSize: "0.8rem", color: "#9DAEC6" }} dir="rtl">{daysLabel(s.days_of_week)}</div>
                    )}
                  </td>
                  <td style={{ padding: "1rem", color: "#9DAEC6" }} dir="ltr">{s.timezone}</td>
                  <td style={{ padding: "1rem" }}>
                    <span
                      style={{
                        fontSize: "0.75rem",
                        fontWeight: 600,
                        padding: "0.25rem 0.75rem",
                        borderRadius: "999px",
                        backgroundColor: s.enabled ? "#064E3B" : "#374151",
                        color: s.enabled ? "#6EE7B7" : "#9DAEC6",
                      }}
                    >
                      {s.enabled ? "مفعّل" : "معطّل"}
                    </span>
                  </td>
                  <td style={{ padding: "1rem" }}>
                    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
                      <button
                        onClick={() => toggleEnabled(s)}
                        style={{ backgroundColor: "transparent", color: "#2E9E9E", border: "1px solid #2E9E9E", padding: "0.35rem 0.8rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem" }}
                      >
                        {s.enabled ? "تعطيل" : "تفعيل"}
                      </button>
                      <button
                        onClick={() => handleDelete(s)}
                        style={{ backgroundColor: "transparent", color: "#F87171", border: "1px solid #7F1D1D", padding: "0.35rem 0.8rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem" }}
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
