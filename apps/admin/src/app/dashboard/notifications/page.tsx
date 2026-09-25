"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * مركز الإشعارات — إرسال حقيقي عبر Supabase Edge Function `notifications`.
 *
 * - لا يُرسل أي شيء من المتصفح بمفاتيح سرّية: المتصفح ينادي الـ Edge Function
 *   برمز دخول المدير (JWT)، والـ Edge Function وحدها تملك service-role ومفاتيح
 *   FCM في أسرار الخادم.
 * - الإرسال الفوري: POST للـ Edge Function ثم توثيق الحملة في
 *   app.notification_campaigns (best-effort).
 * - الإرسال المجدول: يُحفظ صف حملة بحالة scheduled — إرسال الحملات المجدولة
 *   يتم عبر مهمة مجدولة في الخادم (تُفعَّل منفصلةً)، وتُعرض الحالة بصدق هنا.
 * - سجل الحملات يُقرأ من app.notification_campaigns؛ عند غياب الجدول أو
 *   عدم وجود حملات تُعرض حالة فارغة صادقة — لا أرقام ولا رسائل نجاح وهمية.
 */

// نفس قائمة المسارات المسموحة في supabase/functions/notifications/index.ts
const ALLOWED_ROUTES = [
  { value: "/", label: "الرئيسية (/)" },
  { value: "/home", label: "الرئيسية (/home)" },
  { value: "/radio", label: "شاشة الإذاعة (/radio)" },
  { value: "/reciters", label: "دليل القراء (/reciters)" },
  { value: "/quran", label: "المصحف (/quran)" },
  { value: "/library", label: "المكتبة (/library)" },
  { value: "/adhkar", label: "الأذكار (/adhkar)" },
  { value: "/prayer-times", label: "أوقات الصلاة (/prayer-times)" },
  { value: "/settings", label: "الإعدادات (/settings)" },
];

const NOTIFICATION_TYPES = [
  { value: "announcement", label: "إعلان عام" },
  { value: "urgent", label: "طارئ" },
  { value: "live", label: "بث مباشر" },
  { value: "featured", label: "تلاوة مميزة" },
];

const AUDIENCES = [
  { value: "all", label: "كافة الأجهزة ذات الموافقة النشطة" },
  { value: "device", label: "جهاز تجريبي (Installation ID)" },
];

interface CampaignRow {
  id: string;
  title: string;
  body: string;
  notification_type: string;
  target_type: string;
  status: string;
  scheduled_at: string;
  created_at: string;
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

function typeLabel(value: string): string {
  return NOTIFICATION_TYPES.find((t) => t.value === value)?.label ?? value;
}

function statusLabel(value: string): string {
  switch (value) {
    case "draft":
      return "مسودة";
    case "scheduled":
      return "مجدولة";
    case "processing":
      return "قيد الإرسال";
    case "completed":
      return "مُرسلة";
    case "cancelled":
      return "ملغاة";
    default:
      return value;
  }
}

export default function NotificationCenterPage() {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [notificationType, setNotificationType] = useState("announcement");
  const [timing, setTiming] = useState<"now" | "scheduled">("now");
  const [scheduledAt, setScheduledAt] = useState("");
  const [route, setRoute] = useState("/");
  const [audience, setAudience] = useState("all");
  const [testInstallationId, setTestInstallationId] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [statusMsg, setStatusMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const [campaigns, setCampaigns] = useState<CampaignRow[]>([]);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [historyUnavailable, setHistoryUnavailable] = useState(false);

  const functionsBase = process.env.NEXT_PUBLIC_SUPABASE_URL
    ? `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1`
    : null;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

  const loadHistory = useCallback(async () => {
    setHistoryLoading(true);
    setHistoryUnavailable(false);
    if (!supabase) {
      setHistoryLoading(false);
      setHistoryUnavailable(true);
      return;
    }
    const { data, error } = await supabase
      .schema("app")
      .from("notification_campaigns")
      .select("id,title,body,notification_type,target_type,status,scheduled_at,created_at")
      .order("created_at", { ascending: false })
      .limit(50);
    setHistoryLoading(false);
    if (error) {
      // الجدول قد لا يكون موجودًا في بعض البيئات — حالة فارغة صادقة.
      setHistoryUnavailable(true);
      setCampaigns([]);
      return;
    }
    setCampaigns((data ?? []) as CampaignRow[]);
  }, []);

  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  const recordCampaign = async (params: {
    status: "completed" | "scheduled";
    scheduledAtIso: string;
    targetType: "all" | "device";
  }): Promise<boolean> => {
    if (!supabase) return false;
    const { error } = await supabase.schema("app").from("notification_campaigns").insert({
      title: title.trim(),
      body: body.trim(),
      notification_type: notificationType,
      target_type: params.targetType,
      target:
        params.targetType === "device"
          ? { installation_id: testInstallationId.trim() }
          : { audience: "all_opted_in" },
      payload: { route, notification_type: notificationType },
      scheduled_at: params.scheduledAtIso,
      status: params.status,
    });
    return !error;
  };

  const callEdgeFunction = async (targetType: "sendBroadcast" | "sendTest") => {
    if (!supabase) throw new Error("إعدادات Supabase غير مكتملة في بيئة الإدارة.");
    if (!functionsBase) throw new Error("رابط Supabase غير مُهيأ.");
    const { data } = await supabase.auth.getSession();
    const accessToken = data.session?.access_token;
    if (!accessToken) throw new Error("انتهت جلسة الدخول — سجّل الدخول مجددًا.");

    const response = await fetch(`${functionsBase}/notifications`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        title: title.trim(),
        body: body.trim(),
        targetRoute: route,
        targetType,
        testInstallationId: targetType === "sendTest" ? testInstallationId.trim() : undefined,
        notification_type: notificationType,
      }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload?.message || payload?.error || `فشل الإرسال (${response.status})`);
    }
    return payload as {
      success: boolean;
      targetedRecipients: number;
      successCount: number;
      failureCount: number;
      fcmConfigured: boolean;
      mode: string;
    };
  };

  const handleSubmit = async () => {
    setStatusMsg(null);
    if (!title.trim() || !body.trim()) {
      setStatusMsg({ ok: false, text: "يرجى إدخال عنوان ونص الإشعار." });
      return;
    }
    if (audience === "device" && !testInstallationId.trim()) {
      setStatusMsg({ ok: false, text: "أدخل Installation ID للجهاز التجريبي." });
      return;
    }

    // --- الإرسال المجدول: حفظ صف حملة فقط (الإرسال عبر مهمة الخادم) ---
    if (timing === "scheduled") {
      if (!scheduledAt) {
        setStatusMsg({ ok: false, text: "حدّد تاريخ ووقت الإرسال المجدول." });
        return;
      }
      const scheduledDate = new Date(scheduledAt);
      if (Number.isNaN(scheduledDate.getTime()) || scheduledDate.getTime() <= Date.now()) {
        setStatusMsg({ ok: false, text: "وقت الجدولة يجب أن يكون في المستقبل." });
        return;
      }
      setIsSending(true);
      try {
        const recorded = await recordCampaign({
          status: "scheduled",
          scheduledAtIso: scheduledDate.toISOString(),
          targetType: audience === "device" ? "device" : "all",
        });
        if (!recorded) throw new Error("تعذّر حفظ الحملة المجدولة في قاعدة البيانات.");
        setStatusMsg({
          ok: true,
          text: "حُفظت الحملة كمجدولة. ملاحظة: إرسال الحملات المجدولة يتم عبر مهمة مجدولة في الخادم — فعّلها ليتم الإرسال في الموعد.",
        });
        setTitle("");
        setBody("");
        loadHistory();
      } catch (e) {
        setStatusMsg({ ok: false, text: e instanceof Error ? e.message : "تعذّر حفظ الحملة." });
      } finally {
        setIsSending(false);
      }
      return;
    }

    // --- الإرسال الفوري عبر الـ Edge Function ---
    if (!confirm("تأكيد الإرسال الفوري للإشعار؟")) return;
    setIsSending(true);
    try {
      const result = await callEdgeFunction(audience === "device" ? "sendTest" : "sendBroadcast");
      const recorded = await recordCampaign({
        status: "completed",
        scheduledAtIso: new Date().toISOString(),
        targetType: audience === "device" ? "device" : "all",
      });
      const modeNote = result.fcmConfigured
        ? ""
        : " (وضع تجريبي: مفاتيح FCM غير مُهيأة في الخادم — قُبِل الطلب دون إرسال فعلي)";
      setStatusMsg({
        ok: true,
        text:
          `أُرسل عبر الـ Edge Function: ${result.successCount} ناجح / ${result.failureCount} فاشل ` +
          `من ${result.targetedRecipients} جهازًا مستهدفًا${modeNote}.` +
          (recorded ? " وُثّقت الحملة في السجل." : " تعذّر توثيق الحملة في السجل."),
      });
      setTitle("");
      setBody("");
      loadHistory();
    } catch (e) {
      setStatusMsg({
        ok: false,
        text: `فشل الإرسال: ${e instanceof Error ? e.message : String(e)} — لم يُرسل شيء ولم تُسجَّل حملة.`,
      });
    } finally {
      setIsSending(false);
    }
  };

  return (
    <div style={{ maxWidth: "900px" }}>
      <h1 style={{ fontSize: "1.8rem", fontWeight: 700, marginBottom: "0.5rem" }}>مركز الإشعارات</h1>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        الإرسال يتم عبر Supabase Edge Function برمز دخول المدير — لا مفاتيح سرّية في المتصفح إطلاقًا
      </p>

      {statusMsg && (
        <div
          style={{
            backgroundColor: statusMsg.ok ? "#064E3B" : "#7F1D1D",
            color: statusMsg.ok ? "#6EE7B7" : "#FCA5A5",
            padding: "1rem",
            borderRadius: "8px",
            marginBottom: "1.5rem",
            lineHeight: 1.8,
          }}
        >
          {statusMsg.text}
        </div>
      )}

      <div style={{ ...cardStyle, marginBottom: "2rem" }}>
        <div style={{ marginBottom: "1.2rem" }}>
          <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>عنوان الإشعار *</label>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="مثال: بث مباشر لسورة الكهف"
            style={inputStyle}
          />
        </div>

        <div style={{ marginBottom: "1.2rem" }}>
          <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>نص الإشعار *</label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={3}
            placeholder="اكتب رسالة الإشعار…"
            style={inputStyle}
          />
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1.2rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>نوع الإشعار</label>
            <select value={notificationType} onChange={(e) => setNotificationType(e.target.value)} style={inputStyle}>
              {NOTIFICATION_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المسار داخل التطبيق (Allow-list)</label>
            <select value={route} onChange={(e) => setRoute(e.target.value)} style={inputStyle}>
              {ALLOWED_ROUTES.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1.2rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>التوقيت</label>
            <select value={timing} onChange={(e) => setTiming(e.target.value as "now" | "scheduled")} style={inputStyle}>
              <option value="now">فوري</option>
              <option value="scheduled">مجدول</option>
            </select>
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>الجمهور</label>
            <select value={audience} onChange={(e) => setAudience(e.target.value)} style={inputStyle}>
              {AUDIENCES.map((a) => (
                <option key={a.value} value={a.value}>{a.label}</option>
              ))}
            </select>
          </div>
        </div>

        {timing === "scheduled" && (
          <div style={{ marginBottom: "1.2rem" }}>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>تاريخ ووقت الإرسال</label>
            <input
              type="datetime-local"
              value={scheduledAt}
              onChange={(e) => setScheduledAt(e.target.value)}
              style={inputStyle}
            />
            <div style={{ fontSize: "0.8rem", color: "#9DAEC6", marginTop: "0.4rem" }}>
              تُحفظ الحملة كمجدولة في قاعدة البيانات؛ إرسالها الفعلي يتم عبر مهمة مجدولة في الخادم.
            </div>
          </div>
        )}

        {audience === "device" && (
          <div style={{ marginBottom: "1.2rem" }}>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>Installation ID للجهاز التجريبي</label>
            <input
              type="text"
              value={testInstallationId}
              onChange={(e) => setTestInstallationId(e.target.value)}
              placeholder="مثال: 3f2a1b… (UUID)"
              style={inputStyle}
              dir="ltr"
            />
          </div>
        )}

        <div style={{ fontSize: "0.8rem", color: "#9DAEC6", marginBottom: "1.2rem", lineHeight: 1.8 }}>
          ملاحظة: الشرائح المخصصة (Topics/Segments) غير مدعومة بعد في الـ Edge Function —
          الإرسال الحالي يستهدف كافة الأجهزة ذات الموافقة النشطة أو جهازًا تجريبيًا واحدًا.
        </div>

        <button
          onClick={handleSubmit}
          disabled={isSending}
          style={{
            backgroundColor: isSending ? "#374151" : "#2E9E9E",
            color: "#fff",
            border: "none",
            padding: "0.85rem 1.8rem",
            borderRadius: "8px",
            fontWeight: 700,
            cursor: isSending ? "wait" : "pointer",
          }}
        >
          {isSending ? "جارٍ التنفيذ…" : timing === "scheduled" ? "حفظ الحملة المجدولة" : "إرسال الإشعار الآن"}
        </button>
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h2 style={{ fontSize: "1.3rem", fontWeight: 700 }}>سجل الحملات</h2>
        <button
          onClick={loadHistory}
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

      {historyLoading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل السجل…</div>}

      {!historyLoading && historyUnavailable && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🔕</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا يمكن عرض سجل الحملات حاليًا</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            جدول <code dir="ltr">app.notification_campaigns</code> غير متاح أو لا صلاحية قراءة — لا توجد بيانات معروضة بدل الحقيقة.
          </div>
        </div>
      )}

      {!historyLoading && !historyUnavailable && campaigns.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد حملات إشعارات بعد</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            ستظهر هنا الحملات المُرسلة والمجدولة فور إنشائها من النموذج أعلاه.
          </div>
        </div>
      )}

      {!historyLoading && !historyUnavailable && campaigns.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          {campaigns.map((c) => (
            <div key={c.id} style={{ ...cardStyle, padding: "1rem 1.25rem" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "1rem" }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600, color: "#F8F6F1" }}>{c.title}</div>
                  <div style={{ fontSize: "0.85rem", color: "#9DAEC6", marginTop: "0.25rem", lineHeight: 1.7 }}>{c.body}</div>
                  <div style={{ fontSize: "0.75rem", color: "#5B677A", marginTop: "0.5rem" }}>
                    {typeLabel(c.notification_type)} • {c.target_type === "device" ? "جهاز تجريبي" : "الكل"} •{" "}
                    {new Date(c.created_at).toLocaleString("ar")}
                  </div>
                </div>
                <span
                  style={{
                    fontSize: "0.75rem",
                    fontWeight: 600,
                    padding: "0.25rem 0.75rem",
                    borderRadius: "999px",
                    backgroundColor: c.status === "completed" ? "#064E3B" : c.status === "scheduled" ? "#78350F" : "#374151",
                    color: c.status === "completed" ? "#6EE7B7" : c.status === "scheduled" ? "#FCD34D" : "#9DAEC6",
                    flexShrink: 0,
                  }}
                >
                  {statusLabel(c.status)}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
