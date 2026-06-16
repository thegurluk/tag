# Real-Time Location Alert & Navigation App - Project Specification

## 1. Project Overview

This project has two main parts:

1. **Telegram Data Collector + Backend System**

   * Read location-related messages from a specific Telegram group using a Telegram user account.
   * Extract the relevant location name from the message.
   * Convert the location name into exact latitude/longitude coordinates using Google Places / Geocoding APIs.
   * Save the location into the database as an active alert.
   * Move expired alerts into an archive table after 9 hours.

2. **Mobile Application**

   * Show active locations on a Google Maps-based map.
   * Color locations based on how much time has passed since creation:

     * 0-3 hours: Red
     * 3-6 hours: Yellow
     * 6-9 hours: Blue
     * 9+ hours: remove from active map and move to archive
   * Allow users to get route directions from their current location to a selected alert.
   * Provide a motorcycle-oriented route mode that avoids relying heavily on car traffic-based route logic.

---

# 2. Recommended Tech Stack

## Mobile App

Use:

```text
Flutter
Google Maps Flutter SDK
Dio / HTTP client
Location package
Provider / Riverpod / Bloc for state management
```

Preferred:

```text
Flutter + Riverpod
```

---

## Backend API

Use:

```text
Node.js
NestJS
PostgreSQL
PostGIS
Prisma ORM
Redis
BullMQ
Google Places API
Google Geocoding API
Google Routes API
JWT Auth
```

---

## Telegram Listener

Use:

```text
Python
Telethon
Requests / HTTPX
python-dotenv
systemd service for deployment
```

Reason:

The Telegram group is not owned by us, so a Telegram bot may not work. We need to log in using a real Telegram user account and listen to messages from the target group.

---

## Infrastructure

Use:

```text
Ubuntu VPS / AWS EC2
Docker
Docker Compose
Nginx or Caddy
PostgreSQL + PostGIS
Redis
PM2 or systemd
```

Preferred deployment:

```text
Docker Compose
```

---

# 3. High-Level Architecture

```text
Telegram Group
    ↓
Python Telethon Listener
    ↓
Backend API Endpoint
    ↓
Redis Queue
    ↓
Location Worker
    ↓
Text Cleaning + Google Places / Geocoding
    ↓
PostgreSQL + PostGIS
    ↓
NestJS API
    ↓
Flutter Mobile App
    ↓
Google Maps + Google Routes
```

---

# 4. Telegram Message Example

Example incoming message:

```text
PERPA DARÜLACEZE ÖNÜ SİVİL TRAFİK DENDİ 🔥🔥🔥
```

The system should extract only the relevant location part:

```text
PERPA DARÜLACEZE ÖNÜ
```

Then search it as:

```text
PERPA DARÜLACEZE ÖNÜ İstanbul
```

Then get coordinates from Google Places / Geocoding.

---

# 5. Database Design

Use PostgreSQL with PostGIS extension.

## Enable PostGIS

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

---

## users

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(50),
    password_hash TEXT,
    role VARCHAR(50) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

Roles:

```text
user
admin
```

---

## telegram_messages

Stores raw messages received from Telegram.

```sql
CREATE TABLE telegram_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telegram_message_id BIGINT,
    telegram_group_id BIGINT,
    sender_id BIGINT,
    raw_text TEXT NOT NULL,
    received_at TIMESTAMP NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    processing_error TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## active_locations

Stores locations currently visible on the map.

```sql
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

    confidence_score DOUBLE PRECISION DEFAULT 0,

    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,

    status VARCHAR(50) DEFAULT 'active'
);
```

Important:

```text
expires_at = created_at + 9 hours
```

---

## location_archive

Stores expired locations, including coordinates.

```sql
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
    expired_at TIMESTAMP DEFAULT NOW(),

    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## location_reports

Optional table for user reports.

```sql
CREATE TABLE location_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID REFERENCES active_locations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    report_type VARCHAR(100),
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

# 6. Backend API Design

Base URL:

```text
/api
```

---

## Auth Endpoints

```text
POST /auth/register
POST /auth/login
POST /auth/refresh
GET /auth/me
```

---

## Telegram Endpoint

Telegram listener sends new messages here.

```text
POST /telegram/message
```

Request body:

```json
{
  "telegram_message_id": 123456,
  "telegram_group_id": -1001234567890,
  "sender_id": 987654321,
  "raw_text": "PERPA DARÜLACEZE ÖNÜ SİVİL TRAFİK DENDİ 🔥🔥🔥",
  "received_at": "2026-06-16T09:00:00Z"
}
```

Backend behavior:

1. Save raw message into `telegram_messages`.
2. Add message ID into Redis/BullMQ queue.
3. Return success response.

---

## Location Endpoints

### Get active locations

```text
GET /locations/active
```

Response:

```json
[
  {
    "id": "uuid",
    "title": "PERPA DARÜLACEZE ÖNÜ",
    "latitude": 41.064,
    "longitude": 28.984,
    "formatted_address": "Perpa, Şişli, İstanbul",
    "created_at": "2026-06-16T09:00:00Z",
    "expires_at": "2026-06-16T18:00:00Z",
    "color": "red",
    "age_minutes": 75
  }
]
```

Color calculation:

```text
0-180 minutes: red
181-360 minutes: yellow
361-540 minutes: blue
540+ minutes: expired
```

---

### Get nearby active locations

```text
GET /locations/nearby?lat=41.01&lng=29.01&radius=5000
```

Use PostGIS distance query.

---

### Get archive list

```text
GET /locations/archive
```

Admin only or limited public access depending on app logic.

---

### Manually approve/edit location

For admin panel:

```text
PATCH /locations/:id
```

Can update:

```text
title
cleaned_location_text
latitude
longitude
formatted_address
status
```

---

## Route Endpoint

```text
POST /routes/calculate
```

Request:

```json
{
  "origin": {
    "latitude": 41.010,
    "longitude": 29.020
  },
  "destination": {
    "latitude": 41.064,
    "longitude": 28.984
  },
  "mode": "motorcycle"
}
```

Backend behavior:

* If mode is `standard`, use normal Google Routes API.
* If mode is `motorcycle`, use Google Routes API with `TWO_WHEELER` when available.
* Avoid exposing Google API keys directly to the mobile app.

Response:

```json
{
  "distance_meters": 5300,
  "duration_seconds": 720,
  "polyline": "encoded_polyline_here"
}
```

---

# 7. Telegram Listener Design

Use Python + Telethon.

## Telegram Login Flow

First run:

```text
python telegram_listener.py
```

It should ask:

```text
Phone number
Telegram code
2FA password if enabled
```

After successful login, Telethon creates:

```text
telegram_session.session
```

This file stores the Telegram login session.

Important:

```text
Never commit telegram_session.session to GitHub.
Never expose it publicly.
Store it securely on the server.
```

---

## Telegram Listener Responsibilities

1. Log in with Telegram user account.
2. List available dialogs/groups.
3. Select target group ID.
4. Listen for new messages.
5. Send each message to backend endpoint.
6. Avoid duplicate processing.
7. Reconnect automatically if disconnected.

---

## Telegram Listener Example Logic

```python
from telethon import TelegramClient, events
import os
import httpx
from dotenv import load_dotenv

load_dotenv()

api_id = int(os.getenv("TELEGRAM_API_ID"))
api_hash = os.getenv("TELEGRAM_API_HASH")
target_group_id = int(os.getenv("TELEGRAM_TARGET_GROUP_ID"))
backend_url = os.getenv("BACKEND_TELEGRAM_WEBHOOK_URL")

client = TelegramClient("telegram_session", api_id, api_hash)

@client.on(events.NewMessage(chats=target_group_id))
async def handler(event):
    text = event.message.message

    if not text:
        return

    payload = {
        "telegram_message_id": event.message.id,
        "telegram_group_id": target_group_id,
        "sender_id": event.sender_id,
        "raw_text": text,
        "received_at": event.message.date.isoformat()
    }

    async with httpx.AsyncClient() as http:
        await http.post(backend_url, json=payload, timeout=10)

client.start()
client.run_until_disconnected()
```

---

# 8. Message Cleaning Logic

The system must clean Telegram messages before geocoding.

Example raw message:

```text
PERPA DARÜLACEZE ÖNÜ SİVİL TRAFİK DENDİ 🔥🔥🔥
```

Expected cleaned text:

```text
PERPA DARÜLACEZE ÖNÜ
```

---

## Cleaning Rules

Remove:

```text
emoji
fire icons
extra spaces
"sivil trafik"
"dendi"
"var"
"görüldü"
"trafik"
"polis"
"çevirme"
"kontrol"
"ekip"
```

Keep location words:

```text
önü
arkası
yanı
karşısı
girişi
çıkışı
köprü
cadde
sokak
avm
hastane
okul
metro
metrobüs
```

Normalize:

```text
uppercase/lowercase
Turkish characters
multiple spaces
```

Add city context:

```text
İstanbul
```

Example:

```text
cleaned_location_text + " İstanbul"
```

---

# 9. Geocoding / Places Flow

When a Telegram message enters the queue:

1. Load raw message from DB.
2. Clean location text.
3. Search Google Places API with cleaned text.
4. If result found:

   * Save latitude
   * Save longitude
   * Save formatted address
   * Save Google place ID
   * Save confidence score
5. If confidence is low:

   * Mark as pending review
   * Do not show on mobile map until approved
6. If result not found:

   * Save processing error
   * Mark message as failed

---

## Confidence Strategy

Basic scoring idea:

```text
Exact name match: +0.4
City match: +0.2
Known landmark match: +0.2
Google result quality: +0.2
```

Minimum confidence to publish:

```text
0.65
```

If below:

```text
status = pending_review
```

---

# 10. Expiration Logic

Every active location expires after 9 hours.

Use a scheduled worker:

```text
Every 1 minute
```

Logic:

```text
Find active_locations where expires_at <= now()
For each:
    Insert into location_archive
    Delete from active_locations
```

Alternative:

```text
status = expired
```

But preferred:

```text
Move to archive table and remove from active table
```

---

# 11. Mobile App Features

## Main Screens

### 1. Splash Screen

Checks:

```text
auth state
location permission
API status
```

---

### 2. Login/Register Screen

Optional for MVP.

MVP can start without login.

---

### 3. Map Screen

Main screen.

Features:

```text
Google Map
Current user location
Active location markers
Marker colors based on time
Refresh button
Filter button
Route button
```

---

### 4. Location Detail Bottom Sheet

When user taps marker:

Show:

```text
Location title
Formatted address
How long ago it was added
Alert color/status
Distance from user
Route button
Report button
```

---

### 5. Route Screen

Shows:

```text
Route polyline
Distance
Estimated duration
Start navigation button
Route mode selector
```

Modes:

```text
Standard
Motorcycle
```

---

### 6. Archive/List Screen

Shows expired locations as list.

Fields:

```text
title
created time
expired time
address
```

Coordinates should stay in database but do not need to be shown publicly unless needed.

---

### 7. Admin Review Screen

Optional but strongly recommended.

Shows:

```text
Pending messages
Raw Telegram text
Cleaned location text
Google result
Map preview
Approve button
Edit coordinates button
Reject button
```

---

# 12. Marker Color Logic

Mobile app can receive color from backend.

Backend function:

```ts
function getLocationColor(createdAt: Date): 'red' | 'yellow' | 'blue' | 'expired' {
  const diffMinutes = (Date.now() - createdAt.getTime()) / 1000 / 60;

  if (diffMinutes <= 180) return 'red';
  if (diffMinutes <= 360) return 'yellow';
  if (diffMinutes <= 540) return 'blue';
  return 'expired';
}
```

---

# 13. Route Logic

## Standard Route

Use Google Routes API with normal driving mode.

---

## Motorcycle Route

Preferred:

```text
travelMode = TWO_WHEELER
```

If TWO_WHEELER is unavailable in the region:

Fallback:

```text
travelMode = DRIVE
traffic awareness disabled or minimized
```

Do not expose Google API keys in Flutter.

Use:

```text
Flutter app → backend /routes/calculate → Google Routes API
```

---

# 14. Environment Variables

## Backend `.env`

```env
NODE_ENV=development
PORT=3000

DATABASE_URL=postgresql://user:password@localhost:5432/location_app

REDIS_HOST=localhost
REDIS_PORT=6379

JWT_SECRET=change_me

GOOGLE_MAPS_API_KEY=change_me

TELEGRAM_WEBHOOK_SECRET=change_me
```

---

## Telegram Listener `.env`

```env
TELEGRAM_API_ID=123456
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_TARGET_GROUP_ID=-1001234567890
BACKEND_TELEGRAM_WEBHOOK_URL=http://localhost:3000/telegram/message
BACKEND_TELEGRAM_WEBHOOK_SECRET=change_me
```

---

## Flutter `.env`

```env
API_BASE_URL=https://api.yourdomain.com
GOOGLE_MAPS_ANDROID_KEY=change_me
GOOGLE_MAPS_IOS_KEY=change_me
```

---

# 15. Security Requirements

Important rules:

```text
Do not commit .env files.
Do not commit telegram_session.session.
Do not expose Google API keys publicly.
Restrict Google API keys by platform/package/domain.
Validate Telegram webhook requests with a secret.
Rate limit public API endpoints.
Use HTTPS in production.
Use JWT for protected endpoints.
```

---

# 16. Project Folder Structure

Recommended monorepo:

```text
location-alert-project/
│
├── backend/
│   ├── src/
│   │   ├── auth/
│   │   ├── users/
│   │   ├── telegram/
│   │   ├── locations/
│   │   ├── routes/
│   │   ├── workers/
│   │   ├── common/
│   │   └── main.ts
│   ├── prisma/
│   │   └── schema.prisma
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
│
├── telegram-listener/
│   ├── telegram_listener.py
│   ├── requirements.txt
│   ├── .env.example
│   └── README.md
│
├── mobile/
│   ├── lib/
│   │   ├── core/
│   │   ├── features/
│   │   │   ├── map/
│   │   │   ├── locations/
│   │   │   ├── routes/
│   │   │   └── auth/
│   │   └── main.dart
│   └── pubspec.yaml
│
└── README.md
```

---

# 17. Step-by-Step Development Roadmap

## Phase 1 - Backend Base Setup

Tasks:

1. Create NestJS backend.
2. Add PostgreSQL + PostGIS.
3. Add Prisma.
4. Add Redis.
5. Create Docker Compose file.
6. Create health check endpoint.

Expected output:

```text
GET /health → OK
```

---

## Phase 2 - Database Schema

Tasks:

1. Create Prisma schema.
2. Add models:

   * User
   * TelegramMessage
   * ActiveLocation
   * LocationArchive
   * LocationReport
3. Run migrations.
4. Add PostGIS-compatible fields.

Expected output:

```text
Database tables created successfully.
```

---

## Phase 3 - Telegram Webhook Endpoint

Tasks:

1. Create `/telegram/message` endpoint.
2. Validate webhook secret.
3. Save raw Telegram message into `telegram_messages`.
4. Add message to Redis/BullMQ queue.

Expected output:

```text
Telegram message saved and queued.
```

---

## Phase 4 - Telegram Listener

Tasks:

1. Create Python Telethon project.
2. Add login flow.
3. Print dialogs/groups.
4. Configure target group ID.
5. Listen for new messages.
6. Send messages to backend.
7. Prevent duplicate sending.

Expected output:

```text
New Telegram messages arrive in backend DB.
```

---

## Phase 5 - Message Cleaning Worker

Tasks:

1. Create BullMQ worker.
2. Load Telegram message.
3. Clean raw text.
4. Extract location phrase.
5. Save cleaned text.
6. Mark message as processed or failed.

Expected output:

```text
Raw: PERPA DARÜLACEZE ÖNÜ SİVİL TRAFİK DENDİ 🔥🔥🔥
Cleaned: PERPA DARÜLACEZE ÖNÜ
```

---

## Phase 6 - Google Places / Geocoding Integration

Tasks:

1. Add Google Places service.
2. Search cleaned location text + city context.
3. Get latitude/longitude.
4. Save active location.
5. Calculate confidence score.
6. If confidence low, mark as pending review.

Expected output:

```text
Cleaned location becomes exact coordinates.
```

---

## Phase 7 - Active Location API

Tasks:

1. Create `GET /locations/active`.
2. Add marker color calculation.
3. Add age calculation.
4. Add nearby endpoint with PostGIS.

Expected output:

```text
Mobile app can fetch active map markers.
```

---

## Phase 8 - Expiration Worker

Tasks:

1. Create scheduled worker.
2. Run every minute.
3. Find expired active locations.
4. Copy them to `location_archive`.
5. Delete from `active_locations`.

Expected output:

```text
Locations older than 9 hours disappear from map and move to archive.
```

---

## Phase 9 - Flutter Mobile Base

Tasks:

1. Create Flutter app.
2. Add Google Maps Flutter.
3. Request location permission.
4. Show user current location.
5. Connect app to backend.
6. Fetch active locations.
7. Render markers.

Expected output:

```text
Active locations appear on map.
```

---

## Phase 10 - Marker Detail UI

Tasks:

1. Add marker tap event.
2. Show bottom sheet.
3. Display:

   * title
   * address
   * age
   * color/status
   * route button
4. Add refresh button.

Expected output:

```text
User can inspect each active location.
```

---

## Phase 11 - Route Feature

Tasks:

1. Create backend `/routes/calculate`.
2. Integrate Google Routes API.
3. Add standard route.
4. Add motorcycle route.
5. Return polyline, distance, duration.
6. Draw route polyline in Flutter.

Expected output:

```text
User can get directions from current location to selected marker.
```

---

## Phase 12 - Archive/List Screen

Tasks:

1. Create archive endpoint.
2. Create Flutter archive screen.
3. Show expired locations in list.
4. Add pagination.

Expected output:

```text
Expired locations are visible in archive list.
```

---

## Phase 13 - Admin Review Panel

Can be web or mobile.

Tasks:

1. Show pending low-confidence locations.
2. Show raw Telegram message.
3. Show cleaned location text.
4. Show Google result map preview.
5. Allow admin to approve, edit, or reject.
6. Approved records become active map locations.

Expected output:

```text
Wrong or uncertain locations are not published automatically.
```

---

## Phase 14 - Production Deployment

Tasks:

1. Prepare production Docker Compose.
2. Deploy PostgreSQL + Redis + backend.
3. Deploy Telegram listener as systemd service or Docker service.
4. Configure domain.
5. Add HTTPS.
6. Add logging.
7. Add error monitoring.
8. Restrict Google API keys.
9. Backup database.

Expected output:

```text
System runs continuously on production server.
```

---

# 18. MVP Scope

The first working MVP should include only:

```text
Telegram listener
Backend message endpoint
Message cleaning
Google coordinate lookup
PostgreSQL storage
Active location API
Flutter map
Colored markers
9-hour expiration
Basic route button
```

Do not build these in the first MVP:

```text
Full admin panel
User social features
Reports
Payments
Push notifications
Complex AI extraction
```

---

# 19. Future Features

Possible future improvements:

```text
Push notifications for nearby alerts
User-submitted locations
Admin approval workflow
AI-based location extraction
Heatmap view
Favorite areas
Route history
Location reliability score
Duplicate location merging
Automatic city/district detection
```

---

# 20. Important Product Note

The app should be positioned as a real-time community road information and navigation tool.

Avoid designing or describing the app as a tool for illegal activity, avoiding enforcement, or bypassing public safety operations.

The app should focus on:

```text
road awareness
community alerts
navigation support
map-based live updates
driver safety
```

---

# 21. Build Order for Codex / GPT-5.5

Follow this exact order:

```text
1. Create backend NestJS project
2. Add Docker Compose with PostgreSQL PostGIS and Redis
3. Add Prisma schema and migrations
4. Create Telegram message endpoint
5. Create BullMQ queue and worker
6. Create message cleaning service
7. Add Google Places / Geocoding service
8. Create active location table writes
9. Create active location API
10. Create expiration worker
11. Create Telegram listener Python service
12. Test Telegram → backend → DB flow
13. Create Flutter app
14. Add Google Maps
15. Fetch active locations
16. Render colored markers
17. Add marker detail bottom sheet
18. Add route calculation endpoint
19. Draw route polyline
20. Add archive screen
21. Add deployment files
```

---

# 22. Final Expected System Behavior

When a message like this appears in Telegram:

```text
PERPA DARÜLACEZE ÖNÜ SİVİL TRAFİK DENDİ 🔥🔥🔥
```

System should:

```text
1. Telegram listener receives the message.
2. Sends it to backend.
3. Backend stores raw message.
4. Worker cleans the message.
5. Cleaned location becomes: PERPA DARÜLACEZE ÖNÜ
6. Google Places finds coordinates.
7. Backend saves active location.
8. Flutter app shows the marker on map.
9. Marker is red for first 3 hours.
10. Marker becomes yellow after 3 hours.
11. Marker becomes blue after 6 hours.
12. After 9 hours, marker disappears from map.
13. Expired location is saved in archive with coordinates.
14. User can tap marker and get route from current location.
```
