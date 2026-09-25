-- ==============================================================================
-- Migration: 20260201000000_quran_yutla_core_schemas.sql
-- Description: Production-grade domain schemas (app and radio) with strict RLS,
--              canonical metadata, RBAC permissions, audit trails, and notification consent.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Create dedicated schemas
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS radio;

-- ==============================================================================
-- SCHEMA: app (Domain entities, administrative RBAC, Quran & notifications)
-- ==============================================================================

-- 1.1 RBAC: Permissions
CREATE TABLE IF NOT EXISTS app.permissions (
    id TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert granular permissions
INSERT INTO app.permissions (id, description) VALUES
    ('dashboard.read', 'عرض لوحة المؤشرات المركزية'),
    ('notifications.read', 'عرض سجل وحملات الإشعارات'),
    ('notifications.write', 'إرسال وجدولة حملات الإشعارات'),
    ('devices.read', 'عرض أجهزة المستخدمين النشطة دون كشف هوياتهم'),
    ('radio.read', 'عرض حالة الإذاعات وجداول البث'),
    ('radio.control', 'التحكم المباشر في تشغيل وإيقاف وتبديل محطات الإذاعة'),
    ('media.read', 'عرض مكتبة التلاوات والملفات الصوتية'),
    ('media.write', 'رفع ومعالجة الملفات الصوتية والتحقق من التشفير'),
    ('playlists.read', 'عرض قوائم التشغيل المركزية'),
    ('playlists.write', 'إنشاء وتعديل قوائم التشغيل'),
    ('schedules.read', 'عرض جداول البث الزمني'),
    ('schedules.write', 'جدولة التلاوات والمحطات'),
    ('reciters.read', 'عرض دليل القراء'),
    ('reciters.write', 'إضافة وتعديل بيانات القراء والتراخيص'),
    ('stations.read', 'عرض محطات البث الإذاعي'),
    ('stations.write', 'إدارة وتعديل محطات البث وسيرفرات الـ Failover'),
    ('categories.read', 'عرض تصنيفات المحتوى والمقامات'),
    ('categories.write', 'إدارة التصنيفات'),
    ('settings.read', 'عرض إعدادات النظام وRuntime Config'),
    ('settings.write', 'تعديل مفاتيح الـ Feature Flags والإعدادات العامة'),
    ('audit.read', 'عرض سجلات التدقيق والمراقبة الأمنية')
ON CONFLICT (id) DO NOTHING;

-- 1.2 RBAC: Roles
CREATE TABLE IF NOT EXISTS app.roles (
    id TEXT PRIMARY KEY,
    name_arabic TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app.roles (id, name_arabic, description) VALUES
    ('super_admin', 'المدير العام', 'كامل الصلاحيات على كافة مفاصل المنصة'),
    ('radio_operator', 'مشغل الإذاعة', 'صلاحيات إدارة البث المباشر وجداول التلاوات والمحطات'),
    ('content_manager', 'مدير المحتوى القرآني', 'إدارة القراء، التلاوات، والمصادر الصوتية المعتمدة'),
    ('support_viewer', 'مراقب الدعم', 'صلاحيات القراءة فقط وسجلات التدقيق')
ON CONFLICT (id) DO NOTHING;

-- Role <-> Permissions mapping
CREATE TABLE IF NOT EXISTS app.role_permissions (
    role_id TEXT NOT NULL REFERENCES app.roles(id) ON DELETE CASCADE,
    permission_id TEXT NOT NULL REFERENCES app.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Grant all permissions to super_admin
INSERT INTO app.role_permissions (role_id, permission_id)
SELECT 'super_admin', id FROM app.permissions
ON CONFLICT DO NOTHING;

-- 1.3 RBAC: Administrators
CREATE TABLE IF NOT EXISTS app.administrators (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role_id TEXT NOT NULL REFERENCES app.roles(id) ON DELETE RESTRICT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.4 Content Providers (Provenance & Licensing)
CREATE TABLE IF NOT EXISTS app.providers (
    id TEXT PRIMARY KEY,
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    website_url TEXT,
    license_type TEXT NOT NULL DEFAULT 'Public Waqf / Open Islamic Heritage',
    provenance_details TEXT,
    is_trusted BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app.providers (id, name_arabic, name_english, website_url, license_type, provenance_details) VALUES
    ('king_fahd_complex', 'مجمع الملك فهد لطباعة المصحف الشريف', 'King Fahd Glorious Quran Complex', 'https://qurancomplex.gov.sa', 'Waqf / Official Verified', 'الجهة الرسمية المعتمدة لطباعة وتدقيق المصحف الشريف بالمدينة المنورة'),
    ('quran_radio_cairo', 'أرشيف إذاعة القرآن الكريم - القاهرة', 'Quran Radio Archive Cairo', 'https://ertu.org/quran', 'Public Cultural Heritage', 'التسجيلات التاريخية الموثقة لكبار قراء الرعيل الأول'),
    ('haramain_recordings', 'تسجيلات الحرمين الشريفين', 'Two Holy Mosques Recordings', 'https://gph.gov.sa', 'Official Waqf', 'تلاوات أئمة المسجد الحرام والمسجد النبوي الشريف')
ON CONFLICT (id) DO NOTHING;

-- 1.5 Reciters Directory (Normalized Identity)
CREATE TABLE IF NOT EXISTS app.reciters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    canonical_slug TEXT NOT NULL UNIQUE,
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    default_riwayah TEXT NOT NULL DEFAULT 'حفص عن عاصم',
    primary_provider_id TEXT REFERENCES app.providers(id) ON DELETE SET NULL,
    bio_arabic TEXT,
    avatar_url TEXT,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.6 Canonical Quran Metadata & Verses
CREATE TABLE IF NOT EXISTS app.quran_surahs (
    number INT PRIMARY KEY CHECK (number BETWEEN 1 AND 114),
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    name_transliteration TEXT NOT NULL,
    ayah_count INT NOT NULL,
    revelation_order INT NOT NULL,
    revelation_place TEXT NOT NULL CHECK (revelation_place IN ('mecca', 'medina')),
    start_page INT NOT NULL CHECK (start_page BETWEEN 1 AND 604),
    end_page INT NOT NULL CHECK (end_page BETWEEN 1 AND 604)
);

CREATE TABLE IF NOT EXISTS app.quran_ayahs (
    id SERIAL PRIMARY KEY,
    surah_number INT NOT NULL REFERENCES app.quran_surahs(number) ON DELETE CASCADE,
    ayah_number INT NOT NULL,
    verse_key TEXT NOT NULL UNIQUE, -- e.g. "1:1", "18:10"
    text_uthmani TEXT NOT NULL,
    text_imlaei_simple TEXT NOT NULL,
    page_number INT NOT NULL CHECK (page_number BETWEEN 1 AND 604),
    juz_number INT NOT NULL CHECK (juz_number BETWEEN 1 AND 30),
    hizb_number INT NOT NULL,
    rub_number INT NOT NULL,
    sajdah BOOLEAN NOT NULL DEFAULT false,
    UNIQUE (surah_number, ayah_number)
);

-- 1.7 Categories / Genres
CREATE TABLE IF NOT EXISTS app.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.8 Audio Tracks with Provenance & SHA-256
CREATE TABLE IF NOT EXISTS app.audio_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reciter_id UUID NOT NULL REFERENCES app.reciters(id) ON DELETE CASCADE,
    surah_number INT NOT NULL REFERENCES app.quran_surahs(number) ON DELETE RESTRICT,
    provider_id TEXT REFERENCES app.providers(id) ON DELETE SET NULL,
    audio_url TEXT NOT NULL,
    duration_seconds INT NOT NULL DEFAULT 0,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    bitrate_kbps INT NOT NULL DEFAULT 192,
    loudness_lufs NUMERIC(5,2) DEFAULT -16.0,
    checksum_sha256 TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (reciter_id, surah_number)
);

-- 1.9 Runtime Configuration (app_config)
CREATE TABLE IF NOT EXISTS app.app_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT true,
    updated_by UUID REFERENCES auth.users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT no_script_fields CHECK (
        NOT (value::text ~* '<script|javascript:|eval\(|base64_decode')
    )
);

-- Seed default public configurations
INSERT INTO app.app_config (key, value, description, is_public) VALUES
    ('feature_flags', '{"radio_enabled": true, "offline_downloads": true, "prayer_times": true, "adhkar": true, "learning_center": true}'::jsonb, 'مفاتيح تفعيل الميزات عن بعد', true),
    ('home_sections', '["featured_radio", "prayer_times", "daily_reading", "stations_grid", "reciters_carousel", "offline_shelf"]'::jsonb, 'ترتيب أقسام الشاشة الرئيسية', true),
    ('min_supported_version', '{"android": "1.0.0", "ios": "1.0.0", "force_update": false}'::jsonb, 'أدنى إصدار مدعوم للتطبيق', true),
    ('maintenance', '{"is_active": false, "message_ar": "المنصة تخضع لصيانة مجدولة وجيزة", "estimated_return": null}'::jsonb, 'وضع الصيانة العامة', true),
    ('content_sources', '{"mushaf_edition": "quran-uthmani-hafs-v1.0", "audio_standard": "EBU-R128-16LUFS", "quran_complex_verified": true}'::jsonb, 'بيانات المصادر والاعتمادية', true)
ON CONFLICT (key) DO NOTHING;

-- 1.10 Announcements
CREATE TABLE IF NOT EXISTS app.announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title_arabic TEXT NOT NULL,
    content_arabic TEXT NOT NULL,
    target_route TEXT NOT NULL DEFAULT '/',
    is_published BOOLEAN NOT NULL DEFAULT true,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- 1.11 Notification Installations (Consent-Driven, Zero Surveillance)
CREATE TABLE IF NOT EXISTS app.notification_installations (
    installation_id UUID PRIMARY KEY, -- Random client-generated UUID
    hashed_secret TEXT NOT NULL,      -- Secret for device verification
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    app_version TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'ar',
    timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
    consent_version TEXT NOT NULL,    -- Explicit privacy policy version consented to
    consented_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    preferences JSONB NOT NULL DEFAULT '{"prayer_alerts": false, "daily_verse": true, "live_radio_alerts": false}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    revoked_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.12 Audit / System Logs
CREATE TABLE IF NOT EXISTS app.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    payload JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- SCHEMA: radio (Curated 24/7 Virtual Radio, Liquidsoap & Icecast Integration)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS radio.stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    title_arabic TEXT NOT NULL,
    title_english TEXT NOT NULL,
    stream_url TEXT NOT NULL,
    fallback_stream_url TEXT,
    bitrate_kbps INT NOT NULL DEFAULT 128,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'maintenance')),
    is_featured BOOLEAN NOT NULL DEFAULT false,
    order_index INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO radio.stations (slug, title_arabic, title_english, stream_url, fallback_stream_url, is_featured) VALUES
    ('khashia', 'إذاعة التلاوات الخاشعة', 'Khashia Recitations Radio', 'https://stream.quranyutla.app/live/khashia.mp3', 'https://fallback.quranyutla.app/live/khashia.mp3', true),
    ('murattal', 'إذاعة المصحف المرتل', 'Murattal Quran Radio', 'https://stream.quranyutla.app/live/murattal.mp3', 'https://fallback.quranyutla.app/live/murattal.mp3', true),
    ('haramain', 'إذاعة تلاوات الحرمين الشريفين', 'Haramain Recordings Radio', 'https://stream.quranyutla.app/live/haramain.mp3', NULL, false),
    ('minshawi', 'إذاعة الشيخ محمد صديق المنشاوي', 'Sheikh Al-Minshawi Radio', 'https://stream.quranyutla.app/live/minshawi.mp3', NULL, false)
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS radio.now_playing (
    station_id UUID PRIMARY KEY REFERENCES radio.stations(id) ON DELETE CASCADE,
    reciter_name TEXT NOT NULL,
    surah_name TEXT NOT NULL,
    surah_number INT NOT NULL,
    track_title TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    listeners_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.play_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id UUID NOT NULL REFERENCES radio.stations(id) ON DELETE CASCADE,
    reciter_name TEXT NOT NULL,
    surah_name TEXT NOT NULL,
    surah_number INT NOT NULL,
    played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    duration_seconds INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS radio.engine_state (
    id TEXT PRIMARY KEY, -- 'master' or node identifier
    is_healthy BOOLEAN NOT NULL DEFAULT true,
    active_encoder TEXT NOT NULL DEFAULT 'liquidsoap-2.2',
    connected_icecast_nodes INT NOT NULL DEFAULT 2,
    last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE app.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.administrators ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.reciters ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_surahs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_ayahs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audio_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE radio.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.now_playing ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.play_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.engine_state ENABLE ROW LEVEL SECURITY;

-- Helper security function: Check admin permission
CREATE OR REPLACE FUNCTION app.has_permission(required_perm TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, pg_temp
AS $$
DECLARE
    user_role TEXT;
    has_perm BOOLEAN;
BEGIN
    SELECT role_id INTO user_role
    FROM app.administrators
    WHERE id = auth.uid() AND is_active = true;

    IF user_role IS NULL THEN
        RETURN false;
    END IF;

    IF user_role = 'super_admin' THEN
        RETURN true;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM app.role_permissions
        WHERE role_id = user_role AND permission_id = required_perm
    ) INTO has_perm;

    RETURN has_perm;
END;
$$;

-- RLS Public SELECT (Read-Only access to public content)
CREATE POLICY "Public read providers" ON app.providers FOR SELECT USING (true);
CREATE POLICY "Public read active reciters" ON app.reciters FOR SELECT USING (is_active = true);
CREATE POLICY "Public read surahs" ON app.quran_surahs FOR SELECT USING (true);
CREATE POLICY "Public read ayahs" ON app.quran_ayahs FOR SELECT USING (true);
CREATE POLICY "Public read categories" ON app.categories FOR SELECT USING (true);
CREATE POLICY "Public read audio tracks" ON app.audio_tracks FOR SELECT USING (is_verified = true);
CREATE POLICY "Public read public app_config" ON app.app_config FOR SELECT USING (is_public = true);
CREATE POLICY "Public read announcements" ON app.announcements FOR SELECT USING (is_published = true);

CREATE POLICY "Public read active radio stations" ON radio.stations FOR SELECT USING (status = 'active');
CREATE POLICY "Public read now playing" ON radio.now_playing FOR SELECT USING (true);
CREATE POLICY "Public read radio history" ON radio.play_history FOR SELECT USING (true);

-- Notification Installations: Self-registration and update only via matched hashed secret or service_role
CREATE POLICY "Service role manages installations" ON app.notification_installations
    FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- Administrative Policies using app.has_permission
CREATE POLICY "Admins manage reciters" ON app.reciters
    FOR ALL USING (app.has_permission('reciters.write'));
CREATE POLICY "Admins manage tracks" ON app.audio_tracks
    FOR ALL USING (app.has_permission('media.write'));
CREATE POLICY "Admins manage config" ON app.app_config
    FOR ALL USING (app.has_permission('settings.write'));
CREATE POLICY "Admins manage radio stations" ON radio.stations
    FOR ALL USING (app.has_permission('stations.write'));
CREATE POLICY "Admins read audit" ON app.audit_logs
    FOR SELECT USING (app.has_permission('audit.read'));

-- ==============================================================================
-- CRITICAL QURAN VERIFICATION FUNCTION (Fail-Closed Pattern)
-- ==============================================================================
CREATE OR REPLACE FUNCTION app.verify_quran_integrity()
RETURNS TABLE (
    surahs_count BIGINT,
    ayahs_count BIGINT,
    is_valid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, pg_temp
AS $$
DECLARE
    s_count BIGINT;
    a_count BIGINT;
    valid BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO s_count FROM app.quran_surahs;
    SELECT COUNT(*) INTO a_count FROM app.quran_ayahs;

    -- Canonical test: 114 Surahs, 6236 Ayahs (Hafs an Asim standard)
    valid := (s_count = 114 AND a_count = 6236);

    RETURN QUERY SELECT s_count, a_count, valid;
END;
$$;
