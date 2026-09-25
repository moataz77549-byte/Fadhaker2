-- ==============================================================================
-- Migration: 20260301000000_quran_yutla_complete_cloud_backend.sql
-- Description: Complete production schema for Fadhkur (app and radio schemas),
--              Storage Buckets provisioning, RLS policies, RPC functions, and indexes.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS radio;

-- ==============================================================================
-- SCHEMA: app (Domain entities, Profiles, RBAC, Quran, Media, Notifications)
-- ==============================================================================

-- 1. Profiles (Linked to auth.users for optional authenticated members)
CREATE TABLE IF NOT EXISTS app.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    locale TEXT NOT NULL DEFAULT 'ar',
    timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Administrators & RBAC
CREATE TABLE IF NOT EXISTS app.administrators (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS app.roles (
    id TEXT PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS app.permissions (
    id TEXT PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS app.administrator_roles (
    administrator_id UUID NOT NULL REFERENCES app.administrators(id) ON DELETE CASCADE,
    role_id TEXT NOT NULL REFERENCES app.roles(id) ON DELETE CASCADE,
    PRIMARY KEY (administrator_id, role_id)
);

CREATE TABLE IF NOT EXISTS app.role_permissions (
    role_id TEXT NOT NULL REFERENCES app.roles(id) ON DELETE CASCADE,
    permission_id TEXT NOT NULL REFERENCES app.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Insert comprehensive granular permissions
INSERT INTO app.permissions (id, key, description) VALUES
    ('perm_dash_read', 'dashboard.read', 'عرض لوحة المؤشرات المركزية'),
    ('perm_notif_read', 'notifications.read', 'عرض سجل وحملات الإشعارات'),
    ('perm_notif_write', 'notifications.write', 'إرسال وجدولة حملات الإشعارات'),
    ('perm_dev_read', 'devices.read', 'عرض الأجهزة المسجلة بمعرفات مقنعة دون كشف الهويات'),
    ('perm_radio_read', 'radio.read', 'عرض حالة الإذاعات ومحطات البث'),
    ('perm_radio_ctrl', 'radio.control', 'التحكم المباشر في تشغيل وإيقاف وتبديل محطات الإذاعة'),
    ('perm_media_read', 'media.read', 'عرض مكتبة الصوتيات والتلاوات المعتمدة'),
    ('perm_media_write', 'media.write', 'رفع ومعالجة الملفات الصوتية وفحص البصمات'),
    ('perm_play_read', 'playlists.read', 'عرض قوائم التشغيل المركزية'),
    ('perm_play_write', 'playlists.write', 'إنشاء وإدارة قوائم التشغيل'),
    ('perm_sched_read', 'schedules.read', 'عرض جداول البث الزمني'),
    ('perm_sched_write', 'schedules.write', 'جدولة التلاوات وأتمتة الأحداث'),
    ('perm_rec_read', 'reciters.read', 'عرض دليل القراء'),
    ('perm_rec_write', 'reciters.write', 'إضافة وتعديل بيانات القراء والتراخيص'),
    ('perm_st_read', 'stations.read', 'عرض محطات البث الإذاعي'),
    ('perm_st_write', 'stations.write', 'إدارة محطات البث ومسارات التدفق'),
    ('perm_cat_read', 'categories.read', 'عرض تصنيفات المحتوى والمقامات'),
    ('perm_cat_write', 'categories.write', 'إدارة التصنيفات'),
    ('perm_set_read', 'settings.read', 'عرض إعدادات النظام وRuntime Config'),
    ('perm_set_write', 'settings.write', 'تعديل مفاتيح التشغيل عن بعد والإعدادات العامة'),
    ('perm_audit_read', 'audit.read', 'عرض سجل التدقيق والمراقبة الأمنية'),
    ('perm_admin_read', 'administrators.read', 'عرض قائمة المسؤولين والصلاحيات'),
    ('perm_admin_write', 'administrators.write', 'إدارة حسابات المسؤولين وتعيين الأدوار')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO app.roles (id, key, name_ar, name_en, description) VALUES
    ('super_admin', 'super_admin', 'المدير العام', 'Super Administrator', 'كامل الصلاحيات على كافة مفاصل المنصة'),
    ('content_admin', 'content_admin', 'مدير المحتوى القرآني', 'Content Manager', 'إدارة القراء، التلاوات، والمصادر الصوتية المعتمدة'),
    ('radio_operator', 'radio_operator', 'مشغل الإذاعة', 'Radio Operator', 'إدارة البث المباشر ومحطات الإذاعة وجداول التلاوات'),
    ('notification_manager', 'notification_manager', 'مدير الإشعارات', 'Notification Manager', 'إنشاء وجدولة حملات الإشعارات المركزية'),
    ('auditor', 'auditor', 'مراقب التدقيق', 'Security Auditor', 'صلاحيات القراءة فقط لسجلات التدقيق والمراقبة')
ON CONFLICT (id) DO NOTHING;

-- Map all permissions to super_admin
INSERT INTO app.role_permissions (role_id, permission_id)
SELECT 'super_admin', id FROM app.permissions
ON CONFLICT DO NOTHING;

-- 3. Providers & Reciters
CREATE TABLE IF NOT EXISTS app.audio_providers (
    id TEXT PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    base_url TEXT,
    enabled BOOLEAN NOT NULL DEFAULT true,
    priority INT NOT NULL DEFAULT 1,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app.audio_providers (id, key, name, base_url, enabled, priority) VALUES
    ('king_fahd_complex', 'quran_complex', 'مجمع الملك فهد لطباعة المصحف الشريف', 'https://qurancomplex.gov.sa', true, 1),
    ('cairo_radio_archive', 'cairo_radio', 'أرشيف إذاعة القرآن الكريم - القاهرة', 'https://stream.ertu.org', true, 2),
    ('haramain_recordings', 'haramain', 'تسجيلات الرئاسة العامة لشؤون الحرمين', 'https://gph.gov.sa', true, 3)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS app.reciters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    canonical_name TEXT NOT NULL,
    country TEXT,
    bio_ar TEXT,
    bio_en TEXT,
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.reciter_provider_mappings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reciter_id UUID NOT NULL REFERENCES app.reciters(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL REFERENCES app.audio_providers(id) ON DELETE CASCADE,
    provider_reciter_id TEXT NOT NULL,
    riwayah TEXT NOT NULL DEFAULT 'حفص عن عاصم',
    moshaf TEXT NOT NULL DEFAULT 'مرتل',
    bitrate INT NOT NULL DEFAULT 192,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (reciter_id, provider_id, riwayah, moshaf)
);

-- 4. Quran Canonical Dataset
CREATE TABLE IF NOT EXISTS app.quran_surahs (
    number INT PRIMARY KEY CHECK (number BETWEEN 1 AND 114),
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    revelation_type TEXT NOT NULL CHECK (revelation_type IN ('meccan', 'medinan')),
    ayah_count INT NOT NULL,
    page_start INT NOT NULL CHECK (page_start BETWEEN 1 AND 604),
    page_end INT NOT NULL CHECK (page_end BETWEEN 1 AND 604)
);

CREATE TABLE IF NOT EXISTS app.quran_ayahs (
    id SERIAL PRIMARY KEY,
    surah_number INT NOT NULL REFERENCES app.quran_surahs(number) ON DELETE CASCADE,
    ayah_number INT NOT NULL,
    verse_key TEXT NOT NULL UNIQUE,
    page_number INT NOT NULL CHECK (page_number BETWEEN 1 AND 604),
    juz_number INT NOT NULL CHECK (juz_number BETWEEN 1 AND 30),
    hizb_number INT NOT NULL,
    ruku_number INT NOT NULL,
    text_uthmani TEXT NOT NULL,
    text_tajweed TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (surah_number, ayah_number)
);

CREATE TABLE IF NOT EXISTS app.quran_pages (
    page_number INT PRIMARY KEY CHECK (page_number BETWEEN 1 AND 604),
    edition TEXT NOT NULL DEFAULT 'madinah-hafs-v1',
    asset_path TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    width INT NOT NULL DEFAULT 1200,
    height INT NOT NULL DEFAULT 1800,
    manifest_version TEXT NOT NULL DEFAULT '1.0.0',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.quran_audio_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reciter_id UUID NOT NULL REFERENCES app.reciters(id) ON DELETE CASCADE,
    provider_id TEXT REFERENCES app.audio_providers(id) ON DELETE SET NULL,
    surah_number INT NOT NULL REFERENCES app.quran_surahs(number) ON DELETE RESTRICT,
    ayah_number INT,
    bitrate INT NOT NULL DEFAULT 192,
    audio_url TEXT NOT NULL,
    duration_seconds INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (reciter_id, surah_number, ayah_number, bitrate)
);

-- 5. Categories & Stations
CREATE TABLE IF NOT EXISTS app.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    icon TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_system BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO app.categories (slug, name_ar, name_en, icon, is_system, sort_order) VALUES
    ('khashia', 'التلاوات الخاشعة', 'Khashia Recitations', 'heart', true, 1),
    ('murattal', 'المصاحف المرتلة الكاملة', 'Complete Murattal', 'book', true, 2),
    ('haramain', 'تلاوات الحرمين الشريفين', 'Haramain Recordings', 'mosque', true, 3),
    ('radio', 'الإذاعات المباشرة', 'Live Radio Stations', 'radio', true, 4)
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS app.stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    description TEXT,
    logo_url TEXT,
    stream_url TEXT NOT NULL,
    category_id UUID REFERENCES app.categories(id) ON DELETE SET NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('external', 'virtual', 'managed')),
    provider_name TEXT,
    country TEXT,
    is_playable BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    rights_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app.stations (slug, name_ar, name_en, description, stream_url, source_type, provider_name, is_playable, rights_note) VALUES
    ('khashia', 'إذاعة التلاوات الخاشعة', 'Khashia Recitations Radio', 'بث قرآني خاشع مدار 24/7', 'https://stream.quranyutla.app/live/khashia.mp3', 'managed', 'Fadhkur Cluster', true, 'Managed internal playout with -16 LUFS audio normalization'),
    ('murattal', 'إذاعة المصحف المرتل', 'Murattal Quran Radio', 'المصحف المرتل الكامل بأعذب الأصوات', 'https://stream.quranyutla.app/live/murattal.mp3', 'managed', 'Fadhkur Cluster', true, 'Managed internal playout with -16 LUFS audio normalization'),
    ('cairo-quran', 'إذاعة القرآن الكريم من القاهرة', 'Cairo Quran Radio', 'البث الرسمي لإذاعة القرآن الكريم المصرية', 'https://stream.ertu.org/quran', 'external', 'ERTU Egypt', true, 'Public cultural heritage broadcast. Direct client streaming.')
ON CONFLICT (slug) DO NOTHING;

-- 6. Featured Items, Favorites, Playlists, Playback History
CREATE TABLE IF NOT EXISTS app.featured_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type TEXT NOT NULL CHECK (type IN ('surah', 'reciter', 'station', 'playlist', 'announcement')),
    reference_id TEXT NOT NULL,
    title_ar TEXT NOT NULL,
    title_en TEXT NOT NULL,
    subtitle_ar TEXT,
    subtitle_en TEXT,
    image_url TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS app.favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    installation_id UUID,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('surah', 'reciter', 'station', 'ayah')),
    entity_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fav_owner_check CHECK (user_id IS NOT NULL OR installation_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS app.playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    installation_id UUID,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.playlist_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES app.playlists(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL CHECK (item_type IN ('surah', 'track', 'external_stream')),
    reference_id TEXT NOT NULL,
    position INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.playback_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    installation_id UUID,
    content_type TEXT NOT NULL CHECK (content_type IN ('surah', 'radio', 'track')),
    reference_id TEXT NOT NULL,
    reciter_id UUID REFERENCES app.reciters(id) ON DELETE SET NULL,
    surah_number INT,
    ayah_number INT,
    position_seconds INT NOT NULL DEFAULT 0,
    played_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. App Remote Configuration & Announcements (Anti-Code Injection)
CREATE TABLE IF NOT EXISTS app.app_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    is_public BOOLEAN NOT NULL DEFAULT true,
    description TEXT,
    updated_by UUID REFERENCES auth.users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT no_code_injection CHECK (
        NOT (value::text ~* '<script|javascript:|eval\(|base64_decode|system\(')
    )
);

INSERT INTO app.app_config (key, value, is_public, description) VALUES
    ('radio_enabled', 'true'::jsonb, true, 'تفعيل محطات الإذاعة المباشرة'),
    ('offline_downloads_enabled', 'true'::jsonb, true, 'إتاحة تحميل التلاوات للاستماع دون اتصال'),
    ('prayer_enabled', 'true'::jsonb, true, 'عرض مواقيت الصلاة والأذان'),
    ('adhkar_enabled', 'true'::jsonb, true, 'تفعيل حصن المسلم وقسم الأذكار'),
    ('learning_enabled', 'true'::jsonb, true, 'تفعيل قسم مدارسة القرآن والتحفيظ'),
    ('maintenance_mode', 'false'::jsonb, true, 'وضع الصيانة العامة للمنظومة'),
    ('maintenance_message', '{"ar": "المنظومة في صيانة وجيزة دورية", "en": "Brief scheduled maintenance"}'::jsonb, true, 'رسالة شاشة الصيانة'),
    ('min_supported_version', '{"android": "1.0.0", "ios": "1.0.0", "force_update": false}'::jsonb, true, 'أدنى إصدار معتمد'),
    ('home_sections', '["featured", "stations", "reciters", "offline", "categories"]'::jsonb, true, 'ترتيب الأقسام الرئيسية')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS app.announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title_ar TEXT NOT NULL,
    title_en TEXT NOT NULL,
    body_ar TEXT NOT NULL,
    body_en TEXT NOT NULL,
    deep_link TEXT NOT NULL DEFAULT '/',
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    dismissible BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    priority INT NOT NULL DEFAULT 1,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. Installations & Privacy-First Notification Architecture
CREATE TABLE IF NOT EXISTS app.installations (
    id UUID PRIMARY KEY, -- Random client-generated UUID
    installation_secret_hash TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    app_version TEXT NOT NULL,
    build_number INT NOT NULL DEFAULT 1,
    locale TEXT NOT NULL DEFAULT 'ar',
    timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
    notifications_enabled BOOLEAN NOT NULL DEFAULT true,
    firebase_token_encrypted TEXT NOT NULL,
    consent_version TEXT NOT NULL,
    consented_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.notification_preferences (
    installation_id UUID PRIMARY KEY REFERENCES app.installations(id) ON DELETE CASCADE,
    prayer_enabled BOOLEAN NOT NULL DEFAULT false,
    adhkar_enabled BOOLEAN NOT NULL DEFAULT true,
    learning_enabled BOOLEAN NOT NULL DEFAULT true,
    announcements_enabled BOOLEAN NOT NULL DEFAULT true,
    product_updates_enabled BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.notification_campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    notification_type TEXT NOT NULL DEFAULT 'announcement',
    target_type TEXT NOT NULL CHECK (target_type IN ('all', 'segment', 'device')),
    target JSONB NOT NULL DEFAULT '{}'::jsonb,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'processing', 'completed', 'cancelled')),
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.notification_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES app.notification_campaigns(id) ON DELETE CASCADE,
    installation_id UUID NOT NULL REFERENCES app.installations(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'failed', 'revoked')),
    firebase_message_id TEXT,
    error_code TEXT,
    error_message TEXT,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ
);

-- 9. Media Assets & Audio Worker Processing Jobs
CREATE TABLE IF NOT EXISTS app.media_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    media_type TEXT NOT NULL DEFAULT 'audio/mp3',
    storage_bucket TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'audio/mpeg',
    size_bytes BIGINT NOT NULL DEFAULT 0,
    sha256 TEXT NOT NULL,
    duration_seconds INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'UPLOADED' CHECK (status IN ('UPLOADED', 'PROCESSING', 'READY', 'FAILED')),
    rights_status TEXT NOT NULL DEFAULT 'OWNED_OR_VERIFIED_WAQF',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.processing_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    media_asset_id UUID NOT NULL REFERENCES app.media_assets(id) ON DELETE CASCADE,
    job_type TEXT NOT NULL DEFAULT 'EBU_R128_NORMALIZATION',
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'LEASED', 'PROCESSING', 'COMPLETED', 'FAILED')),
    attempt_count INT NOT NULL DEFAULT 0,
    lease_owner TEXT,
    lease_expires_at TIMESTAMPTZ,
    heartbeat_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. External Sources & Virtual Radio Resolution
CREATE TABLE IF NOT EXISTS app.external_sources (
    id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,
    provider TEXT NOT NULL,
    base_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    last_checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS app.virtual_radio_channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS app.virtual_radio_schedule (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id UUID NOT NULL REFERENCES app.virtual_radio_channels(id) ON DELETE CASCADE,
    day_of_week INT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    starts_at TIME NOT NULL,
    ends_at TIME NOT NULL,
    priority INT NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS app.virtual_radio_candidates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id UUID NOT NULL REFERENCES app.virtual_radio_channels(id) ON DELETE CASCADE,
    station_id UUID NOT NULL REFERENCES app.stations(id) ON DELETE CASCADE,
    priority INT NOT NULL DEFAULT 1,
    weight INT NOT NULL DEFAULT 100,
    is_active BOOLEAN NOT NULL DEFAULT true
);

-- 11. Security Audit & System Logs (Append-Only)
CREATE TABLE IF NOT EXISTS app.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_user_id UUID REFERENCES auth.users(id),
    actor_type TEXT NOT NULL DEFAULT 'admin',
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT,
    request_id TEXT,
    ip_hash TEXT,
    metadata JSONB,
    success BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.system_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service TEXT NOT NULL,
    level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'fatal')),
    event TEXT NOT NULL,
    request_id TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- SCHEMA: radio (Managed Playout Cluster, Fencing, Schedules, Liquidsoap)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS radio.engines (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'STANDBY', 'OFFLINE')),
    heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lease_token TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
    schedule_type TEXT NOT NULL CHECK (schedule_type IN ('ONE_TIME', 'DAILY', 'WEEKLY')),
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.schedule_occurrences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schedule_id UUID NOT NULL REFERENCES radio.schedules(id) ON DELETE CASCADE,
    scheduled_for TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED', 'CLAIMED', 'DISPATCHED', 'COMPLETED', 'FAILED')),
    claim_owner TEXT,
    claim_token TEXT,
    claim_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.queue_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    occurrence_id UUID REFERENCES radio.schedule_occurrences(id) ON DELETE CASCADE,
    media_asset_id UUID REFERENCES app.media_assets(id) ON DELETE CASCADE,
    station_id UUID REFERENCES app.stations(id) ON DELETE CASCADE,
    position INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'PLAYING', 'PLAYED', 'SKIPPED', 'FAILED')),
    planned_start TIMESTAMPTZ NOT NULL,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.commands (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    engine_id TEXT REFERENCES radio.engines(id) ON DELETE CASCADE,
    command TEXT NOT NULL CHECK (command IN ('PLAY', 'STOP', 'PAUSE', 'SKIP', 'RELOAD', 'RESTART_SOURCE')),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'ACKNOWLEDGED', 'FAILED')),
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS radio.effects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    command_id UUID REFERENCES radio.commands(id) ON DELETE CASCADE,
    effect_type TEXT NOT NULL,
    payload JSONB,
    status TEXT NOT NULL DEFAULT 'APPLIED',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS radio.now_playing (
    engine_id TEXT PRIMARY KEY REFERENCES radio.engines(id) ON DELETE CASCADE,
    queue_entry_id UUID REFERENCES radio.queue_entries(id) ON DELETE SET NULL,
    media_asset_id UUID REFERENCES app.media_assets(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expected_end_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS radio.play_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    engine_id TEXT REFERENCES radio.engines(id) ON DELETE CASCADE,
    queue_entry_id UUID REFERENCES radio.queue_entries(id) ON DELETE SET NULL,
    media_asset_id UUID REFERENCES app.media_assets(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    result TEXT NOT NULL DEFAULT 'COMPLETED',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS radio.events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    engine_id TEXT REFERENCES radio.engines(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'info' CHECK (severity IN ('info', 'warn', 'error')),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- INDEXES (Performance Optimization for Hot Paths)
-- ==============================================================================

CREATE INDEX IF NOT EXISTS idx_reciters_slug ON app.reciters(slug);
CREATE INDEX IF NOT EXISTS idx_stations_slug ON app.stations(slug);
CREATE INDEX IF NOT EXISTS idx_quran_ayahs_verse_key ON app.quran_ayahs(verse_key);
CREATE INDEX IF NOT EXISTS idx_quran_ayahs_surah_num ON app.quran_ayahs(surah_number);
CREATE INDEX IF NOT EXISTS idx_quran_ayahs_page_num ON app.quran_ayahs(page_number);
CREATE INDEX IF NOT EXISTS idx_quran_ayahs_juz_num ON app.quran_ayahs(juz_number);

CREATE INDEX IF NOT EXISTS idx_installations_last_seen ON app.installations(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_installations_notif_enabled ON app.installations(notifications_enabled);

CREATE INDEX IF NOT EXISTS idx_notif_campaigns_status ON app.notification_campaigns(status);
CREATE INDEX IF NOT EXISTS idx_notif_campaigns_sched_at ON app.notification_campaigns(scheduled_at);

CREATE INDEX IF NOT EXISTS idx_proc_jobs_status ON app.processing_jobs(status);
CREATE INDEX IF NOT EXISTS idx_proc_jobs_lease_exp ON app.processing_jobs(lease_expires_at);

CREATE INDEX IF NOT EXISTS idx_radio_occurrences_sched_for ON radio.schedule_occurrences(scheduled_for);
CREATE INDEX IF NOT EXISTS idx_radio_commands_status ON radio.commands(status);
CREATE INDEX IF NOT EXISTS idx_radio_queue_status ON radio.queue_entries(status);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE app.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.administrators ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.administrator_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audio_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.reciters ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.reciter_provider_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_surahs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_ayahs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quran_audio_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.featured_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.playlist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.playback_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.processing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.external_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.virtual_radio_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.virtual_radio_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.virtual_radio_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.system_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE radio.engines ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.schedule_occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.queue_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.effects ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.now_playing ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.play_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE radio.events ENABLE ROW LEVEL SECURITY;

-- Security Definer: Centralized Admin Permission Checker
CREATE OR REPLACE FUNCTION app.admin_has_permission(required_perm TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, pg_temp
AS $$
DECLARE
    v_admin_id UUID;
    v_has_perm BOOLEAN;
BEGIN
    SELECT id INTO v_admin_id
    FROM app.administrators
    WHERE user_id = auth.uid() AND is_active = true;

    IF v_admin_id IS NULL THEN
        RETURN false;
    END IF;

    -- Super Admin bypass
    IF EXISTS (
        SELECT 1 FROM app.administrator_roles
        WHERE administrator_id = v_admin_id AND role_id = 'super_admin'
    ) THEN
        RETURN true;
    END IF;

    -- Granular check
    SELECT EXISTS (
        SELECT 1
        FROM app.administrator_roles ar
        JOIN app.role_permissions rp ON ar.role_id = rp.role_id
        JOIN app.permissions p ON rp.permission_id = p.id
        WHERE ar.administrator_id = v_admin_id AND (p.key = required_perm OR p.id = required_perm)
    ) INTO v_has_perm;

    RETURN v_has_perm;
END;
$$;

-- Public Read Policies (Allow-listed read-only content for listeners)
CREATE POLICY "Public read active providers" ON app.audio_providers FOR SELECT USING (enabled = true);
CREATE POLICY "Public read active reciters" ON app.reciters FOR SELECT USING (is_active = true);
CREATE POLICY "Public read reciter mappings" ON app.reciter_provider_mappings FOR SELECT USING (is_active = true);
CREATE POLICY "Public read surahs" ON app.quran_surahs FOR SELECT USING (true);
CREATE POLICY "Public read ayahs" ON app.quran_ayahs FOR SELECT USING (true);
CREATE POLICY "Public read quran pages" ON app.quran_pages FOR SELECT USING (true);
CREATE POLICY "Public read audio tracks" ON app.quran_audio_tracks FOR SELECT USING (is_active = true);
CREATE POLICY "Public read categories" ON app.categories FOR SELECT USING (is_active = true);
CREATE POLICY "Public read playable stations" ON app.stations FOR SELECT USING (is_active = true AND is_playable = true);
CREATE POLICY "Public read active featured items" ON app.featured_items FOR SELECT USING (is_active = true);
CREATE POLICY "Public read public app_config" ON app.app_config FOR SELECT USING (is_public = true);
CREATE POLICY "Public read active announcements" ON app.announcements FOR SELECT USING (is_active = true);
CREATE POLICY "Public read now playing" ON radio.now_playing FOR SELECT USING (true);

-- User Private Row Access (Authenticated Users own their profiles/favorites)
CREATE POLICY "Users read own profile" ON app.profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "Users update own profile" ON app.profiles FOR UPDATE USING (id = auth.uid());
CREATE POLICY "Users manage own favorites" ON app.favorites FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users manage own playlists" ON app.playlists FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users manage own playback history" ON app.playback_history FOR ALL USING (user_id = auth.uid());

-- Service Role Bypass (Backend services have unrestricted access)
CREATE POLICY "Service role full access app" ON app.installations FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access notif prefs" ON app.notification_preferences FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access notif campaigns" ON app.notification_campaigns FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access notif deliveries" ON app.notification_deliveries FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access media assets" ON app.media_assets FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access proc jobs" ON app.processing_jobs FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio engines" ON radio.engines FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio schedules" ON radio.schedules FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio occurrences" ON radio.schedule_occurrences FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio queue" ON radio.queue_entries FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio commands" ON radio.commands FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio effects" ON radio.effects FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio history" ON radio.play_history FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
CREATE POLICY "Service role full access radio events" ON radio.events FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- Administrative Policies via app.admin_has_permission
CREATE POLICY "Admins read dashboard" ON app.audit_logs FOR SELECT USING (app.admin_has_permission('dashboard.read'));
CREATE POLICY "Admins manage reciters" ON app.reciters FOR ALL USING (app.admin_has_permission('reciters.write'));
CREATE POLICY "Admins manage stations" ON app.stations FOR ALL USING (app.admin_has_permission('stations.write'));
CREATE POLICY "Admins manage config" ON app.app_config FOR ALL USING (app.admin_has_permission('settings.write'));
CREATE POLICY "Admins manage campaigns" ON app.notification_campaigns FOR ALL USING (app.admin_has_permission('notifications.write'));
CREATE POLICY "Admins view audit" ON app.audit_logs FOR SELECT USING (app.admin_has_permission('audit.read'));

-- ==============================================================================
-- DATABASE RPC FUNCTIONS
-- ==============================================================================

-- 1. Public Home Screen Aggregator RPC
CREATE OR REPLACE FUNCTION app.get_public_home()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, radio, public
AS $$
DECLARE
    v_featured_radio JSONB;
    v_daily_surah JSONB;
    v_active_stations JSONB;
BEGIN
    -- Get current active radio now playing
    SELECT jsonb_build_object(
        'station_slug', s.slug,
        'station_name', s.name_ar,
        'stream_url', s.stream_url,
        'now_playing', np.title,
        'started_at', np.started_at
    ) INTO v_featured_radio
    FROM app.stations s
    LEFT JOIN radio.now_playing np ON true
    WHERE s.slug = 'khashia'
    LIMIT 1;

    -- Canonical Daily Surah (Surah Al-Kahf fallback or recommended reading)
    SELECT jsonb_build_object(
        'surah_number', number,
        'name_ar', name_ar,
        'name_en', name_en,
        'page_start', page_start,
        'ayah_count', ayah_count
    ) INTO v_daily_surah
    FROM app.quran_surahs
    WHERE number = 18
    LIMIT 1;

    -- Top active stations
    SELECT jsonb_agg(jsonb_build_object(
        'slug', slug,
        'name_ar', name_ar,
        'stream_url', stream_url,
        'source_type', source_type
    )) INTO v_active_stations
    FROM (
        SELECT slug, name_ar, stream_url, source_type
        FROM app.stations
        WHERE is_active = true AND is_playable = true
        LIMIT 6
    ) t;

    RETURN jsonb_build_object(
        'featured_radio', COALESCE(v_featured_radio, '{}'::jsonb),
        'daily_surah', COALESCE(v_daily_surah, '{}'::jsonb),
        'stations', COALESCE(v_active_stations, '[]'::jsonb),
        'server_timestamp', NOW()
    );
END;
$$;

-- 2. Public Reciters Directory RPC
CREATE OR REPLACE FUNCTION app.get_public_reciters()
RETURNS TABLE (
    id UUID,
    slug TEXT,
    name_ar TEXT,
    name_en TEXT,
    canonical_name TEXT,
    bio_ar TEXT,
    image_url TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = app, public
AS $$
    SELECT id, slug, name_ar, name_en, canonical_name, bio_ar, image_url
    FROM app.reciters
    WHERE is_active = true
    ORDER BY name_ar ASC;
$$;

-- 3. Public Reciter Tracks RPC
CREATE OR REPLACE FUNCTION app.get_reciter_tracks(p_reciter_id UUID)
RETURNS TABLE (
    track_id UUID,
    surah_number INT,
    surah_name_ar TEXT,
    audio_url TEXT,
    duration_seconds INT,
    bitrate INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = app, public
AS $$
    SELECT
        t.id AS track_id,
        t.surah_number,
        s.name_ar AS surah_name_ar,
        t.audio_url,
        t.duration_seconds,
        t.bitrate
    FROM app.quran_audio_tracks t
    JOIN app.quran_surahs s ON t.surah_number = s.number
    WHERE t.reciter_id = p_reciter_id AND t.is_active = true
    ORDER BY t.surah_number ASC;
$$;

-- 4. Public Active Stations RPC
CREATE OR REPLACE FUNCTION app.get_public_stations()
RETURNS TABLE (
    id UUID,
    slug TEXT,
    name_ar TEXT,
    name_en TEXT,
    stream_url TEXT,
    source_type TEXT,
    provider_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = app, public
AS $$
    SELECT id, slug, name_ar, name_en, stream_url, source_type, provider_name
    FROM app.stations
    WHERE is_active = true AND is_playable = true
    ORDER BY name_ar ASC;
$$;

-- 5. Public Station By Slug RPC
CREATE OR REPLACE FUNCTION app.get_station_by_slug(p_slug TEXT)
RETURNS TABLE (
    id UUID,
    slug TEXT,
    name_ar TEXT,
    name_en TEXT,
    description TEXT,
    stream_url TEXT,
    source_type TEXT,
    provider_name TEXT,
    rights_note TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = app, public
AS $$
    SELECT id, slug, name_ar, name_en, description, stream_url, source_type, provider_name, rights_note
    FROM app.stations
    WHERE slug = p_slug AND is_active = true
    LIMIT 1;
$$;

-- 6. Public Runtime Config RPC
CREATE OR REPLACE FUNCTION app.get_public_config()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = app, public
AS $$
DECLARE
    v_config JSONB;
BEGIN
    SELECT jsonb_object_agg(key, value)
    INTO v_config
    FROM app.app_config
    WHERE is_public = true;

    RETURN COALESCE(v_config, '{}'::jsonb);
END;
$$;

-- 7. Audit Event Creator RPC
CREATE OR REPLACE FUNCTION app.create_audit_event(
    p_action TEXT,
    p_resource_type TEXT,
    p_resource_id TEXT,
    p_request_id TEXT,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, public
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO app.audit_logs (
        actor_user_id,
        actor_type,
        action,
        resource_type,
        resource_id,
        request_id,
        metadata,
        success
    ) VALUES (
        auth.uid(),
        CASE WHEN auth.uid() IS NOT NULL THEN 'authenticated' ELSE 'system' END,
        p_action,
        p_resource_type,
        p_resource_id,
        p_request_id,
        p_metadata,
        true
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

-- 8. Audio Processing Job Claim & Heartbeat RPCs (Anti-Split Brain)
CREATE OR REPLACE FUNCTION app.claim_processing_job(p_worker_id TEXT, p_lease_seconds INT DEFAULT 300)
RETURNS TABLE (
    job_id UUID,
    media_asset_id UUID,
    storage_bucket TEXT,
    storage_path TEXT,
    media_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, public
AS $$
DECLARE
    v_job_id UUID;
BEGIN
    -- Select and lock a pending or expired job atomically
    SELECT id INTO v_job_id
    FROM app.processing_jobs
    WHERE status = 'PENDING'
       OR (status = 'LEASED' AND lease_expires_at < NOW())
    ORDER BY created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF v_job_id IS NOT NULL THEN
        UPDATE app.processing_jobs
        SET status = 'LEASED',
            lease_owner = p_worker_id,
            lease_expires_at = NOW() + (p_lease_seconds || ' seconds')::interval,
            heartbeat_at = NOW(),
            attempt_count = attempt_count + 1,
            updated_at = NOW()
        WHERE id = v_job_id;

        RETURN QUERY
        SELECT j.id, m.id, m.storage_bucket, m.storage_path, m.media_type
        FROM app.processing_jobs j
        JOIN app.media_assets m ON j.media_asset_id = m.id
        WHERE j.id = v_job_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION app.heartbeat_processing_job(p_job_id UUID, p_worker_id TEXT, p_extend_seconds INT DEFAULT 300)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, public
AS $$
DECLARE
    v_updated BOOLEAN;
BEGIN
    UPDATE app.processing_jobs
    SET heartbeat_at = NOW(),
        lease_expires_at = NOW() + (p_extend_seconds || ' seconds')::interval,
        updated_at = NOW()
    WHERE id = p_job_id AND lease_owner = p_worker_id AND status = 'LEASED';

    RETURN FOUND;
END;
$$;

-- 9. Radio Occurrence Claim RPC (Deterministic Anti-Double-Play)
CREATE OR REPLACE FUNCTION app.claim_radio_occurrence(p_engine_id TEXT, p_claim_token TEXT, p_lease_seconds INT DEFAULT 60)
RETURNS TABLE (
    occurrence_id UUID,
    schedule_id UUID,
    scheduled_for TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = radio, public
AS $$
DECLARE
    v_occ_id UUID;
BEGIN
    SELECT id INTO v_occ_id
    FROM radio.schedule_occurrences
    WHERE status = 'SCHEDULED'
       OR (status = 'CLAIMED' AND claim_expires_at < NOW())
    ORDER BY scheduled_for ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF v_occ_id IS NOT NULL THEN
        UPDATE radio.schedule_occurrences
        SET status = 'CLAIMED',
            claim_owner = p_engine_id,
            claim_token = p_claim_token,
            claim_expires_at = NOW() + (p_lease_seconds || ' seconds')::interval,
            updated_at = NOW()
        WHERE id = v_occ_id;

        RETURN QUERY
        SELECT id, schedule_id, scheduled_for
        FROM radio.schedule_occurrences
        WHERE id = v_occ_id;
    END IF;
END;
$$;

-- ==============================================================================
-- 8 SPECIALIZED STORAGE BUCKETS PROVISIONING & POLICIES
-- ==============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('quran-mushaf', 'quran-mushaf', true, 52428800, ARRAY['image/webp', 'application/json']),
    ('reciter-artwork', 'reciter-artwork', true, 10485760, ARRAY['image/webp', 'image/jpeg', 'image/png']),
    ('station-artwork', 'station-artwork', true, 10485760, ARRAY['image/webp', 'image/jpeg', 'image/png']),
    ('app-content', 'app-content', true, 52428800, ARRAY['application/json', 'text/plain']),
    ('media-source-private', 'media-source-private', false, 524288000, ARRAY['audio/mpeg', 'audio/wav', 'audio/flac']),
    ('media-processed-private', 'media-processed-private', false, 524288000, ARRAY['audio/mpeg', 'application/json']),
    ('admin-uploads-private', 'admin-uploads-private', false, 524288000, ARRAY['audio/mpeg', 'application/json', 'image/webp']),
    ('exports-private', 'exports-private', false, 104857600, ARRAY['application/json', 'text/csv', 'application/zip'])
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit;

-- Public Storage Read Policies
CREATE POLICY "Public read quran-mushaf" ON storage.objects FOR SELECT
    USING (bucket_id = 'quran-mushaf');

CREATE POLICY "Public read reciter-artwork" ON storage.objects FOR SELECT
    USING (bucket_id = 'reciter-artwork');

CREATE POLICY "Public read station-artwork" ON storage.objects FOR SELECT
    USING (bucket_id = 'station-artwork');

CREATE POLICY "Public read app-content" ON storage.objects FOR SELECT
    USING (bucket_id = 'app-content');

-- Private Buckets Strict Service Role & Admin Access
CREATE POLICY "Service role and admins access private storage" ON storage.objects FOR ALL
    USING (
        auth.jwt() ->> 'role' = 'service_role' OR
        app.admin_has_permission('media.write')
    );
