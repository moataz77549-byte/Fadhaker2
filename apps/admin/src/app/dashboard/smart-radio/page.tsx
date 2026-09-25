"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";

type Rule = {
  id: string;
  rule_key: string;
  title_ar: string;
  trigger_type: string;
  prayer_name: string | null;
  start_offset_minutes: number | null;
  end_offset_minutes: number | null;
  starts_at: string | null;
  ends_at: string | null;
  priority: number;
  source_pool_key: string;
  transition_policy: string;
  refresh_minutes: number;
  is_active: boolean;
};

type Source = {
  id: string;
  program_key: string;
  source_type: string;
  weight: number;
  priority: number;
  is_active: boolean;
  stations: { name_ar: string; health_status: string; status: string } | null;
};

type OverrideRow = {
  id: string;
  title_ar: string;
  starts_at: string;
  expires_at: string;
  reason: string;
  is_active: boolean;
  source_id: string | null;
  source_pool_key: string | null;
};

type Preview = {
  channel: { slug: string; name: string };
  program: {
    key: string; title: string; sourceName: string; sourceType: string;
    validUntil: string; transitionPolicy: string; fallbackMode?: boolean;
  };
  next: { title: string; startsAt: string } | null;
};

const card: React.CSSProperties = {
  backgroundColor: "#172235",
  border: "1px solid #243B6B",
  borderRadius: 12,
  padding: 16,
};

const input: React.CSSProperties = {
  backgroundColor: "#0E1726",
  color: "#F8F6F1",
  border: "1px solid #243B6B",
  borderRadius: 7,
  padding: "0.5rem 0.65rem",
};

export default function SmartRadioPage() {
  const [channelId, setChannelId] = useState<string | null>(null);
  const [channelActive, setChannelActive] = useState(false);
  const [rules, setRules] = useState<Rule[]>([]);
  const [sources, setSources] = useState<Source[]>([]);
  const [overrides, setOverrides] = useState<OverrideRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const [timezone, setTimezone] = useState("Asia/Aden");
  const [localDateTime, setLocalDateTime] = useState("2026-09-25T20:00:00");
  const [fajr, setFajr] = useState("04:45");
  const [dhuhr, setDhuhr] = useState("12:00");
  const [asr, setAsr] = useState("15:20");
  const [maghrib, setMaghrib] = useState("18:05");
  const [isha, setIsha] = useState("19:20");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [savingRule, setSavingRule] = useState<string | null>(null);
  const [savingSource, setSavingSource] = useState<string | null>(null);

  const [overrideSource, setOverrideSource] = useState("");
  const [overrideTitle, setOverrideTitle] = useState("بث خاص مؤقت");
  const [overrideReason, setOverrideReason] = useState("");
  const [overrideMinutes, setOverrideMinutes] = useState("30");

  const pools = useMemo(
    () => Array.from(new Set(sources.map(source => source.program_key))).sort(),
    [sources],
  );

  const load = useCallback(async () => {
    if (!supabase) return;
    setLoading(true);
    setError(null);
    try {
      const ch = await supabase.schema("app").from("virtual_radio_channels")
        .select("id,is_active").eq("slug", "fadhkur-smart").single();
      if (ch.error) throw new Error(ch.error.message);
      setChannelId(ch.data.id);
      setChannelActive(ch.data.is_active);

      const [rulesRes, sourcesRes, overridesRes] = await Promise.all([
        supabase.schema("app").from("virtual_radio_rules")
          .select("id,rule_key,title_ar,trigger_type,prayer_name,start_offset_minutes,end_offset_minutes,starts_at,ends_at,priority,source_pool_key,transition_policy,refresh_minutes,is_active")
          .eq("channel_id", ch.data.id).order("priority", { ascending: false }),
        supabase.schema("app").from("virtual_radio_sources")
          .select("id,program_key,source_type,weight,priority,is_active,stations(name_ar,health_status,status)")
          .eq("channel_id", ch.data.id)
          .order("program_key").order("priority", { ascending: false }),
        supabase.schema("app").from("virtual_radio_overrides")
          .select("id,title_ar,starts_at,expires_at,reason,is_active,source_id,source_pool_key")
          .eq("channel_id", ch.data.id).order("created_at", { ascending: false }).limit(20),
      ]);
      if (rulesRes.error) throw new Error(rulesRes.error.message);
      if (sourcesRes.error) throw new Error(sourcesRes.error.message);
      if (overridesRes.error) throw new Error(overridesRes.error.message);
      setRules((rulesRes.data ?? []) as Rule[]);
      setSources((sourcesRes.data ?? []) as unknown as Source[]);
      setOverrides((overridesRes.data ?? []) as OverrideRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل إعداد إذاعة فذكر.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function toggleChannel() {
    if (!supabase || !channelId) return;
    const next = !channelActive;
    const { error: updateError } = await supabase.schema("app")
      .from("virtual_radio_channels").update({ is_active: next }).eq("id", channelId);
    if (updateError) return setError(updateError.message);
    setChannelActive(next);
    setMessage(next ? "تم تفعيل إذاعة فذكر الذكية." : "تم تعطيل إذاعة فذكر الذكية.");
  }

  async function toggleRule(rule: Rule) {
    if (!supabase) return;
    const { error: updateError } = await supabase.schema("app")
      .from("virtual_radio_rules").update({ is_active: !rule.is_active }).eq("id", rule.id);
    if (updateError) return setError(updateError.message);
    setRules(current => current.map(item =>
      item.id === rule.id ? { ...item, is_active: !item.is_active } : item));
  }

  function patchRule(id: string, patch: Partial<Rule>) {
    setRules(current => current.map(rule =>
      rule.id === id ? { ...rule, ...patch } : rule));
  }

  async function saveRule(rule: Rule) {
    if (!supabase) return;
    if (!Number.isInteger(rule.priority) || rule.priority < 0 || rule.priority > 1000) {
      return setError("أولوية القاعدة يجب أن تكون رقمًا صحيحًا بين 0 و1000.");
    }
    if (!Number.isInteger(rule.refresh_minutes) ||
        rule.refresh_minutes < 5 || rule.refresh_minutes > 120) {
      return setError("مدة التحديث يجب أن تكون بين 5 و120 دقيقة.");
    }
    if (rule.trigger_type === "CLOCK" && (!rule.starts_at || !rule.ends_at)) {
      return setError("قواعد الوقت تحتاج وقت بداية ونهاية.");
    }
    if (rule.trigger_type === "PRAYER_RELATIVE") {
      if (rule.start_offset_minutes == null || rule.end_offset_minutes == null) {
        return setError("قاعدة الصلاة تحتاج إزاحة بداية ونهاية.");
      }
      if (rule.end_offset_minutes < rule.start_offset_minutes) {
        return setError("نهاية نافذة الصلاة يجب ألا تسبق بدايتها.");
      }
    }
    if (!rule.source_pool_key.trim()) return setError("Source pool مطلوب.");
    setSavingRule(rule.id);
    setError(null);
    const { error: updateError } = await supabase.schema("app")
      .from("virtual_radio_rules")
      .update({
        title_ar: rule.title_ar.trim(),
        priority: rule.priority,
        source_pool_key: rule.source_pool_key,
        transition_policy: rule.transition_policy,
        refresh_minutes: rule.refresh_minutes,
        starts_at: rule.starts_at,
        ends_at: rule.ends_at,
        start_offset_minutes: rule.start_offset_minutes,
        end_offset_minutes: rule.end_offset_minutes,
      })
      .eq("id", rule.id);
    setSavingRule(null);
    if (updateError) return setError(updateError.message);
    setMessage(`تم حفظ قاعدة «${rule.title_ar}» وتسجيلها في سجل التدقيق.`);
  }

  function patchSource(id: string, patch: Partial<Source>) {
    setSources(current => current.map(source =>
      source.id === id ? { ...source, ...patch } : source));
  }

  async function saveSource(source: Source) {
    if (!supabase) return;
    if (!Number.isInteger(source.weight) || source.weight < 1 || source.weight > 10000) {
      return setError("وزن المصدر يجب أن يكون بين 1 و10000.");
    }
    if (!Number.isInteger(source.priority) || source.priority < -1000 || source.priority > 1000) {
      return setError("أولوية المصدر خارج النطاق المسموح.");
    }
    setSavingSource(source.id);
    setError(null);
    const { error: updateError } = await supabase.schema("app")
      .from("virtual_radio_sources")
      .update({
        weight: source.weight,
        priority: source.priority,
        is_active: source.is_active,
      })
      .eq("id", source.id);
    setSavingSource(null);
    if (updateError) return setError(updateError.message);
    setMessage("تم حفظ إعداد المصدر وتسجيله في سجل التدقيق.");
  }

  async function previewNow() {
    if (!supabase) return;
    setPreviewBusy(true);
    setError(null);
    try {
      const { data, error: invokeError } = await supabase.functions.invoke(
        "smart-radio-resolve",
        {
          body: {
            channel: "fadhkur-smart",
            timezone,
            localDateTime,
            instantUtc: new Date().toISOString(),
            prayerTimes: { fajr, dhuhr, asr, maghrib, isha },
          },
        },
      );
      if (invokeError) throw new Error(invokeError.message);
      if (data?.error) throw new Error(data.error.message ?? data.error.code);
      setPreview(data as Preview);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّرت المعاينة.");
    } finally {
      setPreviewBusy(false);
    }
  }

  async function createOverride() {
    if (!supabase || !channelId) return;
    const minutes = Number.parseInt(overrideMinutes, 10);
    if (!overrideSource) return setError("اختر مصدرًا للتجاوز المؤقت.");
    if (!overrideReason.trim()) return setError("سبب التجاوز مطلوب لسجل التدقيق.");
    if (!Number.isFinite(minutes) || minutes < 5 || minutes > 720) {
      return setError("مدة التجاوز يجب أن تكون بين 5 دقائق و12 ساعة.");
    }
    const { data: userData } = await supabase.auth.getUser();
    const startsAt = new Date();
    const expiresAt = new Date(startsAt.getTime() + minutes * 60_000);
    const { error: insertError } = await supabase.schema("app")
      .from("virtual_radio_overrides").insert({
        channel_id: channelId,
        source_id: overrideSource,
        title_ar: overrideTitle.trim() || "بث خاص مؤقت",
        starts_at: startsAt.toISOString(),
        expires_at: expiresAt.toISOString(),
        reason: overrideReason.trim(),
        created_by: userData.user?.id ?? null,
      });
    if (insertError) return setError(insertError.message);
    setOverrideReason("");
    setMessage("تم إنشاء التجاوز المؤقت وسينتهي تلقائيًا.");
    await load();
  }

  async function stopOverride(row: OverrideRow) {
    if (!supabase) return;
    const { error: updateError } = await supabase.schema("app")
      .from("virtual_radio_overrides").update({ is_active: false }).eq("id", row.id);
    if (updateError) return setError(updateError.message);
    await load();
  }

  return <section dir="rtl" style={{ maxWidth: 1180, margin: "0 auto" }}>
    <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
      <div>
        <h1 style={{ marginBottom: 4 }}>إذاعة فذكر الذكية</h1>
        <p style={{ color: "#9DAEC6", marginTop: 0 }}>
          برمجة شخصية حسب الوقت ومواقيت الصلاة دون تخزين الموقع الدقيق.
        </p>
      </div>
      <button onClick={() => void toggleChannel()}
        style={{ ...input, borderColor: channelActive ? "#10B981" : "#7F1D1D" }}>
        {channelActive ? "مفعّلة ✓" : "معطّلة"}
      </button>
    </div>

    {error && <p role="alert" style={{ color: "#FCA5A5" }}>{error}</p>}
    {message && <p role="status" style={{ color: "#34D399" }}>{message}</p>}
    {loading ? <p>جارٍ التحميل…</p> : <>
      <div style={{ display: "grid", gridTemplateColumns: "1.25fr 0.75fr", gap: 16 }}>
        <div style={card}>
          <h2>القواعد</h2>
          <div style={{ display: "grid", gap: 12 }}>
            {rules.map(rule => <div key={rule.id}
              style={{ borderBottom: "1px solid #243B6B", paddingBottom: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
                <input
                  style={{ ...input, flex: 1, fontWeight: 700 }}
                  value={rule.title_ar}
                  onChange={e => patchRule(rule.id, { title_ar: e.target.value })}
                />
                <button onClick={() => void toggleRule(rule)} style={input}>
                  {rule.is_active ? "نشطة" : "متوقفة"}
                </button>
              </div>
              <div style={{ color: "#9DAEC6", fontSize: 13, marginTop: 6 }}>
                {rule.trigger_type}
                {rule.prayer_name ? ` · ${rule.prayer_name}` : ""}
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginTop: 8 }}>
                <label>الأولوية{" "}
                  <input style={{ ...input, width: 85 }} type="number" min={0} max={1000}
                    value={rule.priority}
                    onChange={e => patchRule(rule.id, { priority: Number(e.target.value) })} />
                </label>
                <label>Source pool{" "}
                  <select style={input} value={rule.source_pool_key}
                    onChange={e => patchRule(rule.id, { source_pool_key: e.target.value })}>
                    {pools.map(pool => <option key={pool} value={pool}>{pool}</option>)}
                  </select>
                </label>
                <label>التحديث/دقيقة{" "}
                  <input style={{ ...input, width: 85 }} type="number" min={5} max={120}
                    value={rule.refresh_minutes}
                    onChange={e => patchRule(rule.id, { refresh_minutes: Number(e.target.value) })} />
                </label>
                <label>الانتقال{" "}
                  <select style={input} value={rule.transition_policy}
                    onChange={e => patchRule(rule.id, { transition_policy: e.target.value })}>
                    <option value="FINISH_ITEM">FINISH_ITEM</option>
                    <option value="SOFT_DEADLINE">SOFT_DEADLINE</option>
                    <option value="IMMEDIATE">IMMEDIATE</option>
                  </select>
                </label>
                {rule.trigger_type === "CLOCK" && <>
                  <label>من{" "}
                    <input style={input} type="time"
                      value={(rule.starts_at ?? "").slice(0, 5)}
                      onChange={e => patchRule(rule.id, {
                        starts_at: e.target.value ? `${e.target.value}:00` : null,
                      })} />
                  </label>
                  <label>إلى{" "}
                    <input style={input} type="time"
                      value={(rule.ends_at ?? "").slice(0, 5)}
                      onChange={e => patchRule(rule.id, {
                        ends_at: e.target.value ? `${e.target.value}:00` : null,
                      })} />
                  </label>
                </>}
                {rule.trigger_type === "PRAYER_RELATIVE" && <>
                  <label>بداية/دقيقة{" "}
                    <input style={{ ...input, width: 85 }} type="number" min={-720} max={720}
                      value={rule.start_offset_minutes ?? 0}
                      onChange={e => patchRule(rule.id, {
                        start_offset_minutes: Number(e.target.value),
                      })} />
                  </label>
                  <label>نهاية/دقيقة{" "}
                    <input style={{ ...input, width: 85 }} type="number" min={-720} max={720}
                      value={rule.end_offset_minutes ?? 0}
                      onChange={e => patchRule(rule.id, {
                        end_offset_minutes: Number(e.target.value),
                      })} />
                  </label>
                </>}
                <button style={input} disabled={savingRule === rule.id}
                  onClick={() => void saveRule(rule)}>
                  {savingRule === rule.id ? "جارٍ الحفظ…" : "حفظ القاعدة"}
                </button>
              </div>
            </div>)}
          </div>
        </div>

        <div style={card}>
          <h2>مصادر البرامج</h2>
          {pools.map(pool => <div key={pool} style={{ marginBottom: 16 }}>
            <strong>{pool}</strong>
            <div style={{ display: "grid", gap: 6, marginTop: 6 }}>
              {sources.filter(source => source.program_key === pool).map(source =>
                <div key={source.id}
                  style={{ borderTop: "1px solid #243B6B", paddingTop: 6 }}>
                  <div style={{ color: source.is_active ? "#F8F6F1" : "#64748B", fontSize: 13 }}>
                    {source.stations?.name_ar ?? source.source_type}
                    {source.stations ? ` · ${source.stations.health_status}` : ""}
                  </div>
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 4 }}>
                    <label>وزن{" "}
                      <input style={{ ...input, width: 75 }} type="number" min={1} max={10000}
                        value={source.weight}
                        onChange={e => patchSource(source.id, { weight: Number(e.target.value) })} />
                    </label>
                    <label>أولوية{" "}
                      <input style={{ ...input, width: 75 }} type="number"
                        value={source.priority}
                        onChange={e => patchSource(source.id, { priority: Number(e.target.value) })} />
                    </label>
                    <button style={input}
                      onClick={() => patchSource(source.id, { is_active: !source.is_active })}>
                      {source.is_active ? "مفعّل" : "متوقف"}
                    </button>
                    <button style={input} disabled={savingSource === source.id}
                      onClick={() => void saveSource(source)}>
                      {savingSource === source.id ? "…" : "حفظ"}
                    </button>
                  </div>
                </div>)}
            </div>
          </div>)}
        </div>
      </div>

      <div style={{ ...card, marginTop: 16 }}>
        <h2>معاينة القرار</h2>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          <input style={input} value={timezone} onChange={e => setTimezone(e.target.value)}
            placeholder="Asia/Aden" dir="ltr" />
          <input style={input} value={localDateTime} onChange={e => setLocalDateTime(e.target.value)}
            dir="ltr" />
          {[
            { label: "الفجر", value: fajr, setter: setFajr },
            { label: "الظهر", value: dhuhr, setter: setDhuhr },
            { label: "العصر", value: asr, setter: setAsr },
            { label: "المغرب", value: maghrib, setter: setMaghrib },
            { label: "العشاء", value: isha, setter: setIsha },
          ].map(({ label, value, setter }) =>
            <label key={label}>{label}{" "}
              <input style={{ ...input, width: 80 }} value={value}
                onChange={e => setter(e.target.value)}
                dir="ltr" />
            </label>)}
          <button onClick={() => void previewNow()} disabled={previewBusy} style={input}>
            {previewBusy ? "جارٍ الحل…" : "Preview"}
          </button>
        </div>
        {preview && <div style={{ marginTop: 12 }}>
          <strong>الآن: {preview.program.title}</strong>
          <div>{preview.program.sourceName} · {preview.program.sourceType}</div>
          <div style={{ color: "#9DAEC6" }}>
            الانتقال: {preview.program.transitionPolicy} · صالح حتى {preview.program.validUntil}
          </div>
          <div style={{ color: "#2E9E9E" }}>
            {preview.next ? `التالي: ${preview.next.title} عند ${preview.next.startsAt}` : "لا يوجد انتقال قريب"}
          </div>
        </div>}
      </div>

      <div style={{ ...card, marginTop: 16 }}>
        <h2>تجاوز يدوي مؤقت</h2>
        <p style={{ color: "#9DAEC6" }}>كل تجاوز يحتاج سببًا ووقت انتهاء، ولا يمكن أن يكون دائمًا.</p>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          <select style={input} value={overrideSource} onChange={e => setOverrideSource(e.target.value)}>
            <option value="">اختر المصدر</option>
            {sources.filter(source => source.is_active).map(source =>
              <option key={source.id} value={source.id}>
                {source.stations?.name_ar ?? source.program_key} — {source.program_key}
              </option>)}
          </select>
          <input style={input} value={overrideTitle} onChange={e => setOverrideTitle(e.target.value)}
            placeholder="عنوان البرنامج" />
          <input style={input} value={overrideReason} onChange={e => setOverrideReason(e.target.value)}
            placeholder="سبب التجاوز" />
          <input style={{ ...input, width: 100 }} value={overrideMinutes}
            onChange={e => setOverrideMinutes(e.target.value)} inputMode="numeric" />
          <button style={input} onClick={() => void createOverride()}>تشغيل مؤقت</button>
        </div>
        <div style={{ marginTop: 12 }}>
          {overrides.map(row => <div key={row.id}
            style={{ display: "flex", justifyContent: "space-between", gap: 10, borderTop: "1px solid #243B6B", padding: "8px 0" }}>
            <span>
              {row.title_ar} · حتى {new Date(row.expires_at).toLocaleString("ar")} · {row.reason}
            </span>
            {row.is_active && new Date(row.expires_at).getTime() > Date.now() &&
              <button style={input} onClick={() => void stopOverride(row)}>إيقاف</button>}
          </div>)}
        </div>
      </div>
    </>}
  </section>;
}
