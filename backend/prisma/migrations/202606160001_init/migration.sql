CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(50),
    password_hash TEXT,
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE telegram_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telegram_message_id BIGINT NOT NULL,
    telegram_group_id BIGINT NOT NULL,
    sender_id BIGINT,
    raw_text TEXT NOT NULL,
    received_at TIMESTAMP NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    processing_error TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT telegram_messages_telegram_message_id_telegram_group_id_key
        UNIQUE (telegram_message_id, telegram_group_id)
);

CREATE TABLE active_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telegram_message_id UUID REFERENCES telegram_messages(id) ON DELETE SET NULL,
    title VARCHAR(255),
    raw_message TEXT,
    cleaned_location_text TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    geom GEOGRAPHY(Point, 4326),
    formatted_address TEXT,
    google_place_id TEXT,
    confidence_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'active'
);

CREATE INDEX active_locations_status_idx ON active_locations(status);
CREATE INDEX active_locations_expires_at_idx ON active_locations(expires_at);
CREATE INDEX active_locations_geom_idx ON active_locations USING GIST (geom);

CREATE TABLE location_archive (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_location_id UUID,
    telegram_message_id UUID,
    title VARCHAR(255),
    raw_message TEXT,
    cleaned_location_text TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    geom GEOGRAPHY(Point, 4326),
    formatted_address TEXT,
    google_place_id TEXT,
    confidence_score DOUBLE PRECISION,
    original_created_at TIMESTAMP,
    expired_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX location_archive_geom_idx ON location_archive USING GIST (geom);

CREATE TABLE location_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES active_locations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    report_type VARCHAR(100),
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
