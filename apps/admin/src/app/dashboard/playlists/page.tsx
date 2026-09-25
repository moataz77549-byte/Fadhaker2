"use client";

import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

/**
 * إدارة قوائم التشغيل — CRUD حقيقي على جدولي app.playlists و app.playlist_items.
 *
 * الـ schema المعتمد (من migration ‏20260830040900):
 *   app.playlists: id, station_id (إلزامي → app.stations), name, description,
 *     shuffle, repeat, is_active, version, created_at, updated_at, deleted_at.
 *     (unique ‏(station_id, name))
 *   app.playlist_items: id, playlist_id, media_id (→ app.media), position,
 *     weight, created_at. (unique ‏(playlist_id, position))
 *
 * - عدد المقاطع يُحسب فعليًا من playlist_items.
 * - عند غياب الجداول تُعرض حالة غير متاح صادقة — لا بيانات ثابتة.
 */

interface PlaylistRow {
  id: string;
  station_id: string;
  name: string;
  description: string | null;
  shuffle: boolean;
  repeat: boolean;
  is_active: boolean;
  stations: { name_ar: string } | null;
  item_count: number;
}

interface PlaylistItemRow {
  id: string;
  playlist_id: string;
  position: number;
  weight: number;
  media: { title: string } | null;
}

interface StationOption {
  id: string;
  name_ar: string;
}

interface MediaOption {
  id: string;
  title: string;
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

const emptyForm = { station_id: "", name: "", description: "", shuffle: false, repeat: true, is_active: true };

export default function PlaylistsAdminPage() {
  const [playlists, setPlaylists] = useState<PlaylistRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tableMissing, setTableMissing] = useState(false);
  const [stations, setStations] = useState<StationOption[]>([]);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [items, setItems] = useState<PlaylistItemRow[]>([]);
  const [itemsLoading, setItemsLoading] = useState(false);
  const [mediaOptions, setMediaOptions] = useState<MediaOption[]>([]);
  const [addMediaId, setAddMediaId] = useState("");
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
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
    const [{ data: stationData }, { data, error }] = await Promise.all([
      client.schema("app").from("stations").select("id,name_ar").eq("is_active", true).is("deleted_at", null).order("name_ar"),
      client
        .schema("app")
        .from("playlists")
        .select("id,station_id,name,description,shuffle,repeat,is_active,stations(name_ar)")
        .is("deleted_at", null)
        .order("name", { ascending: true }),
    ]);
    setStations((stationData ?? []) as StationOption[]);
    setLoading(false);
    if (error) {
      setTableMissing(true);
      setPlaylists([]);
      return;
    }
    const rows = (((data ?? []) as unknown) as Array<Record<string, unknown>>).map((r) => ({
      ...(r as object),
      stations: Array.isArray(r.stations) ? (r.stations[0] as { name_ar: string } | undefined) ?? null : (r.stations as { name_ar: string } | null),
    })) as Omit<PlaylistRow, "item_count">[];
    const withCounts: PlaylistRow[] = await Promise.all(
      rows.map(async (p) => {
        const { count } = await client
          .schema("app")
          .from("playlist_items")
          .select("id", { count: "exact", head: true })
          .eq("playlist_id", p.id);
        return { ...p, item_count: count ?? 0 };
      })
    );
    setPlaylists(withCounts);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const loadItems = useCallback(async (playlistId: string) => {
    setItemsLoading(true);
    setItems([]);
    const client = supabase;
    if (!client) {
      setItemsLoading(false);
      return;
    }
    const [{ data: itemData, error: itemError }, { data: mediaData }] = await Promise.all([
      client
        .schema("app")
        .from("playlist_items")
        .select("id,playlist_id,position,weight,media(title)")
        .eq("playlist_id", playlistId)
        .order("position", { ascending: true }),
      client
        .schema("app")
        .from("media")
        .select("id,title")
        .eq("status", "READY")
        .is("deleted_at", null)
        .order("title", { ascending: true })
        .limit(50),
    ]);
    setItemsLoading(false);
    if (!itemError) {
      const normalized = (((itemData ?? []) as unknown) as Array<Record<string, unknown>>).map((r) => ({
        ...(r as object),
        media: Array.isArray(r.media) ? (r.media[0] as { title: string } | undefined) ?? null : (r.media as { title: string } | null),
      })) as PlaylistItemRow[];
      setItems(normalized);
    }
    setMediaOptions((mediaData ?? []) as MediaOption[]);
    setAddMediaId("");
  }, []);

  const toggleExpand = (id: string) => {
    if (expandedId === id) {
      setExpandedId(null);
      setItems([]);
    } else {
      setExpandedId(id);
      loadItems(id);
    }
  };

  const validate = (): string | null => {
    if (!form.station_id) return "اختر المحطة المرتبطة بالقائمة.";
    if (!form.name.trim()) return "اسم قائمة التشغيل مطلوب.";
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
      station_id: form.station_id,
      name: form.name.trim(),
      description: form.description.trim() || null,
      shuffle: form.shuffle,
      repeat: form.repeat,
      is_active: form.is_active,
    };
    try {
      if (editingId) {
        const { error } = await supabase.schema("app").from("playlists").update(payload).eq("id", editingId);
        if (error) throw error;
      } else {
        const { error } = await supabase.schema("app").from("playlists").insert(payload);
        if (error) throw error;
      }
      setForm(emptyForm);
      setEditingId(null);
      setMsg({ ok: true, text: editingId ? "حُفظت التعديلات." : "أُنشئت قائمة التشغيل." });
      load();
    } catch (e) {
      setMsg({ ok: false, text: `تعذّر الحفظ: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = (p: PlaylistRow) => {
    setEditingId(p.id);
    setForm({
      station_id: p.station_id,
      name: p.name,
      description: p.description ?? "",
      shuffle: p.shuffle,
      repeat: p.repeat,
      is_active: p.is_active,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const handleDelete = async (p: PlaylistRow) => {
    if (!supabase) return;
    if (!confirm(`حذف قائمة «${p.name}» وجميع عناصرها نهائيًا؟`)) return;
    const { error } = await supabase.schema("app").from("playlists").delete().eq("id", p.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر الحذف: ${error.message}` });
      return;
    }
    setMsg({ ok: true, text: "حُذفت قائمة التشغيل." });
    load();
  };

  const toggleActive = async (p: PlaylistRow) => {
    if (!supabase) return;
    const { error } = await supabase.schema("app").from("playlists").update({ is_active: !p.is_active }).eq("id", p.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّر التحديث: ${error.message}` });
      return;
    }
    load();
  };

  const handleAddItem = async (playlistId: string) => {
    if (!supabase || !addMediaId) return;
    const nextPosition = items.length > 0 ? Math.max(...items.map((i) => i.position)) + 1 : 0;
    const { error } = await supabase
      .schema("app")
      .from("playlist_items")
      .insert({ playlist_id: playlistId, media_id: addMediaId, position: nextPosition, weight: 1 });
    if (error) {
      setMsg({ ok: false, text: `تعذّرت الإضافة: ${error.message}` });
      return;
    }
    setMsg({ ok: true, text: "أُضيف العنصر إلى القائمة." });
    loadItems(playlistId);
    load();
  };

  const handleRemoveItem = async (item: PlaylistItemRow) => {
    if (!supabase) return;
    if (!confirm("إزالة هذا العنصر من القائمة؟")) return;
    const { error } = await supabase.schema("app").from("playlist_items").delete().eq("id", item.id);
    if (error) {
      setMsg({ ok: false, text: `تعذّرت الإزالة: ${error.message}` });
      return;
    }
    loadItems(item.playlist_id);
    load();
  };

  const set = (patch: Partial<typeof emptyForm>) => setForm((f) => ({ ...f, ...patch }));

  return (
    <div>
      <h1 style={{ fontSize: "1.8rem", fontWeight: 700, marginBottom: "0.5rem" }}>قوائم التشغيل المركزية</h1>
      <p style={{ color: "#2E9E9E", marginBottom: "2rem" }}>
        إدارة قوائم التشغيل المرتبطة بالمحطات من جدولي <code dir="ltr">app.playlists</code> و <code dir="ltr">app.playlist_items</code>
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
          {editingId ? "تعديل قائمة التشغيل" : "إنشاء قائمة جديدة"}
        </h2>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>المحطة المرتبطة *</label>
            <select value={form.station_id} onChange={(e) => set({ station_id: e.target.value })} style={inputStyle}>
              <option value="">اختر المحطة…</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>{s.name_ar}</option>
              ))}
            </select>
          </div>
          <div>
            <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>اسم القائمة *</label>
            <input
              type="text"
              value={form.name}
              onChange={(e) => set({ name: e.target.value })}
              placeholder="ورد قيام الليل"
              style={inputStyle}
            />
          </div>
        </div>
        <div style={{ marginBottom: "1rem" }}>
          <label style={{ display: "block", marginBottom: "0.4rem", fontSize: "0.9rem" }}>الوصف (اختياري)</label>
          <input
            type="text"
            value={form.description}
            onChange={(e) => set({ description: e.target.value })}
            placeholder="وصف مختصر للقائمة"
            style={inputStyle}
          />
        </div>
        <div style={{ display: "flex", gap: "1.5rem", alignItems: "center", marginBottom: "1.25rem", flexWrap: "wrap" }}>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input type="checkbox" checked={form.shuffle} onChange={(e) => set({ shuffle: e.target.checked })} />
            تشغيل عشوائي
          </label>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input type="checkbox" checked={form.repeat} onChange={(e) => set({ repeat: e.target.checked })} />
            تكرار القائمة
          </label>
          <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input type="checkbox" checked={form.is_active} onChange={(e) => set({ is_active: e.target.checked })} />
            قائمة مفعّلة
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
            {saving ? "جارٍ الحفظ…" : editingId ? "حفظ التعديلات" : "إنشاء القائمة"}
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
        <h2 style={{ fontSize: "1.3rem", fontWeight: 700 }}>قوائم التشغيل الحالية</h2>
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

      {loading && <div style={{ color: "#9DAEC6" }}>جارٍ تحميل قوائم التشغيل…</div>}

      {!loading && tableMissing && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>🎵</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>جداول قوائم التشغيل غير متاحة</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6", lineHeight: 1.8 }}>
            جدولا <code dir="ltr">app.playlists</code> / <code dir="ltr">app.playlist_items</code> غير موجودين في هذه البيئة أو لا صلاحية قراءة —
            طبّق الـ migration الخاص بهما من مالك قاعدة البيانات ثم أعد التحميل.
          </div>
        </div>
      )}

      {!loading && !tableMissing && playlists.length === 0 && (
        <div style={{ ...cardStyle, textAlign: "center", padding: "2.5rem" }}>
          <div style={{ fontSize: "2rem", marginBottom: "1rem" }}>📭</div>
          <div style={{ fontWeight: 600, color: "#F8F6F1", marginBottom: "0.5rem" }}>لا توجد قوائم تشغيل بعد</div>
          <div style={{ fontSize: "0.9rem", color: "#9DAEC6" }}>
            أنشئ أول قائمة من النموذج أعلاه.
          </div>
        </div>
      )}

      {!loading && !tableMissing && playlists.length > 0 && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", gap: "1.2rem" }}>
          {playlists.map((pl) => (
            <div key={pl.id} style={cardStyle}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "0.75rem", marginBottom: "0.5rem" }}>
                <h3 style={{ fontSize: "1.1rem", fontWeight: 700, margin: 0 }}>{pl.name}</h3>
                <span
                  style={{
                    fontSize: "0.75rem",
                    fontWeight: 600,
                    padding: "0.25rem 0.75rem",
                    borderRadius: "999px",
                    backgroundColor: pl.is_active ? "#064E3B" : "#374151",
                    color: pl.is_active ? "#6EE7B7" : "#9DAEC6",
                    flexShrink: 0,
                  }}
                >
                  {pl.is_active ? "مفعّلة" : "معطّلة"}
                </span>
              </div>
              <div style={{ color: "#2E9E9E", fontSize: "0.85rem", marginBottom: "1rem" }}>
                المحطة: {pl.stations?.name_ar ?? "—"}
              </div>
              <div style={{ fontSize: "0.9rem", color: "#9DAEC6", marginBottom: "0.4rem" }}>عدد المقاطع: {pl.item_count}</div>
              <div style={{ fontSize: "0.9rem", color: "#9DAEC6", marginBottom: "1.2rem" }}>
                {pl.shuffle ? "تشغيل عشوائي" : "تشغيل مرتب"} • {pl.repeat ? "تكرار" : "بدون تكرار"}
              </div>
              {expandedId === pl.id && (
                <div style={{ marginBottom: "1rem", borderTop: "1px solid #243B6B", paddingTop: "1rem" }}>
                  {itemsLoading && <div style={{ color: "#9DAEC6", fontSize: "0.85rem" }}>جارٍ تحميل العناصر…</div>}
                  {!itemsLoading && items.length === 0 && (
                    <div style={{ color: "#9DAEC6", fontSize: "0.85rem" }}>لا توجد عناصر في هذه القائمة بعد.</div>
                  )}
                  {!itemsLoading && items.length > 0 && (
                    <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem", marginBottom: "1rem" }}>
                      {items.map((it) => (
                        <div key={it.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", fontSize: "0.85rem", backgroundColor: "#0E1726", padding: "0.5rem 0.75rem", borderRadius: "6px" }}>
                          <span style={{ color: "#F8F6F1" }}>
                            <span style={{ color: "#2E9E9E", fontFamily: "monospace", marginLeft: "0.5rem" }}>{it.position}</span>
                            {it.media?.title ?? "مادة محذوفة"}
                          </span>
                          <button
                            onClick={() => handleRemoveItem(it)}
                            style={{ backgroundColor: "transparent", color: "#F87171", border: "1px solid #7F1D1D", padding: "0.2rem 0.6rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.75rem" }}
                          >
                            إزالة
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  <div style={{ display: "flex", gap: "0.5rem" }}>
                    <select value={addMediaId} onChange={(e) => setAddMediaId(e.target.value)} style={{ ...inputStyle, flex: 1, padding: "0.5rem" }}>
                      <option value="">اختر مادة جاهزة للإضافة…</option>
                      {mediaOptions.map((m) => (
                        <option key={m.id} value={m.id}>{m.title}</option>
                      ))}
                    </select>
                    <button
                      onClick={() => handleAddItem(pl.id)}
                      disabled={!addMediaId}
                      style={{
                        backgroundColor: addMediaId ? "#2E9E9E" : "#374151",
                        color: "#fff",
                        border: "none",
                        padding: "0.5rem 1rem",
                        borderRadius: "6px",
                        cursor: addMediaId ? "pointer" : "not-allowed",
                        fontSize: "0.85rem",
                        flexShrink: 0,
                      }}
                    >
                      إضافة
                    </button>
                  </div>
                </div>
              )}
              <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
                <button
                  onClick={() => toggleExpand(pl.id)}
                  style={{ backgroundColor: "#243B6B", color: "#fff", border: "none", padding: "0.5rem 1rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.85rem" }}
                >
                  {expandedId === pl.id ? "إخفاء العناصر" : "عرض العناصر"}
                </button>
                <button
                  onClick={() => toggleActive(pl)}
                  style={{ backgroundColor: "transparent", color: "#2E9E9E", border: "1px solid #2E9E9E", padding: "0.5rem 1rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.85rem" }}
                >
                  {pl.is_active ? "تعطيل" : "تفعيل"}
                </button>
                <button
                  onClick={() => handleEdit(pl)}
                  style={{ backgroundColor: "transparent", color: "#9DAEC6", border: "1px solid #243B6B", padding: "0.5rem 1rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.85rem" }}
                >
                  تعديل
                </button>
                <button
                  onClick={() => handleDelete(pl)}
                  style={{ backgroundColor: "transparent", color: "#EF4444", border: "1px solid #EF4444", padding: "0.5rem 1rem", borderRadius: "6px", cursor: "pointer", fontSize: "0.85rem" }}
                >
                  حذف
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
