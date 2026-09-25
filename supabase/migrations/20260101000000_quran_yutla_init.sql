-- Fadhkur (فذكر) Initial Database Schema
-- Production-ready schema with RLS and Audit logging

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Canonical Surahs Index
CREATE TABLE IF NOT EXISTS public.surahs (
    id SERIAL PRIMARY KEY,
    number INT NOT NULL UNIQUE CHECK (number BETWEEN 1 AND 114),
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    name_transliteration TEXT NOT NULL,
    ayah_count INT NOT NULL,
    revelation_type TEXT NOT NULL CHECK (revelation_type IN ('meccan', 'medinan')),
    page_number INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Reciters Table
CREATE TABLE IF NOT EXISTS public.reciters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_arabic TEXT NOT NULL,
    name_english TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    bio_arabic TEXT,
    rewaya TEXT NOT NULL DEFAULT 'حفص عن عاصم',
    avatar_url TEXT,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Audio Tracks Table
CREATE TABLE IF NOT EXISTS public.audio_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reciter_id UUID NOT NULL REFERENCES public.reciters(id) ON DELETE CASCADE,
    surah_number INT NOT NULL REFERENCES public.surahs(number) ON DELETE RESTRICT,
    audio_url TEXT NOT NULL,
    duration_seconds INT NOT NULL DEFAULT 0,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    bitrate_kbps INT NOT NULL DEFAULT 128,
    format TEXT NOT NULL DEFAULT 'mp3',
    loudness_lufs NUMERIC(5,2) DEFAULT -16.0,
    waveform JSONB,
    checksum_sha256 TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (reciter_id, surah_number)
);

-- 4. Managed Radio Stations
CREATE TABLE IF NOT EXISTS public.radio_stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title_arabic TEXT NOT NULL,
    title_english TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    stream_url TEXT NOT NULL,
    fallback_stream_url TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'scheduled', 'offline')),
    current_reciter_id UUID REFERENCES public.reciters(id) ON DELETE SET NULL,
    current_surah_number INT REFERENCES public.surahs(number) ON DELETE SET NULL,
    listeners_count INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Radio Schedules / Playlists
CREATE TABLE IF NOT EXISTS public.radio_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    radio_id UUID NOT NULL REFERENCES public.radio_stations(id) ON DELETE CASCADE,
    audio_track_id UUID NOT NULL REFERENCES public.audio_tracks(id) ON DELETE CASCADE,
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end TIMESTAMPTZ NOT NULL,
    order_index INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Remote App Configuration & Maintenance
CREATE TABLE IF NOT EXISTS public.app_remote_config (
    id SERIAL PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. Audit Logs Table (Administrative accountability)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID,
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT,
    payload JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security (RLS) on all public tables
ALTER TABLE public.surahs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reciters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audio_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.radio_stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.radio_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_remote_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Public read policies for active content (Zero authentication required for listeners)
CREATE POLICY "Public can read surahs" ON public.surahs FOR SELECT USING (true);
CREATE POLICY "Public can read active reciters" ON public.reciters FOR SELECT USING (is_active = true);
CREATE POLICY "Public can read audio tracks" ON public.audio_tracks FOR SELECT USING (true);
CREATE POLICY "Public can read active radio stations" ON public.radio_stations FOR SELECT USING (is_active = true);
CREATE POLICY "Public can read radio schedules" ON public.radio_schedules FOR SELECT USING (true);
CREATE POLICY "Public can read remote config" ON public.app_remote_config FOR SELECT USING (true);

-- Admin mutation policies (Requires authenticated service_role or admin claim)
CREATE POLICY "Admin write reciters" ON public.reciters FOR ALL USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
CREATE POLICY "Admin write audio tracks" ON public.audio_tracks FOR ALL USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
CREATE POLICY "Admin write radio stations" ON public.radio_stations FOR ALL USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
CREATE POLICY "Admin write radio schedules" ON public.radio_schedules FOR ALL USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
CREATE POLICY "Admin write remote config" ON public.app_remote_config FOR ALL USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
CREATE POLICY "Admin read audit logs" ON public.audit_logs FOR SELECT USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'admin');
