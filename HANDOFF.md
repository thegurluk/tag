# Location Alert Project - Handoff Notes

Bu dokuman, projede su ana kadar yapilanlari ve yeni bir chatte nereden devam edilecegini ozetler.

## Genel Durum

Proje `c:\Users\gurlu\Desktop\tag` altinda monorepo olarak kuruldu.

Ana hedef:

- Telegram grubundan konumla ilgili mesajlari almak
- Backend'e kaydetmek
- Worker ile mesaji temizlemek
- Google Geocoding ile koordinata cevirmek
- Aktif lokasyonlari API'den sunmak
- Daha sonra Flutter mobil uygulamada Google Maps uzerinde marker olarak gostermek

Su an backend, worker, Redis, PostgreSQL/PostGIS ve Telegram listener sunucuda calisiyor.

Production backend dis adresi:

```text
http://46.101.231.239:3010
```

Health endpoint:

```text
http://46.101.231.239:3010/api/health
```

Aktif lokasyon endpoint:

```text
http://46.101.231.239:3010/api/locations/active
```

## Repo Yapisi

```text
.
├── backend/
│   ├── src/
│   │   ├── common/
│   │   ├── health/
│   │   ├── locations/
│   │   ├── prisma/
│   │   ├── routes/
│   │   ├── telegram/
│   │   ├── workers/
│   │   ├── app.module.ts
│   │   ├── main.ts
│   │   └── worker.ts
│   ├── prisma/
│   │   ├── migrations/
│   │   ├── init-postgis.sql
│   │   └── schema.prisma
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── package.json
│   └── README.md
├── telegram-listener/
│   ├── telegram_listener.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── README.md
├── deploy/
│   └── Caddyfile
├── docker-compose.prod.yml
├── .env.production.example
├── README.md
├── plan.md
└── HANDOFF.md
```

## Backend

Framework:

```text
NestJS
Prisma
PostgreSQL/PostGIS
Redis
BullMQ
Google Geocoding / Routes API
```

Backend global prefix:

```text
/api
```

### Implemented Endpoints

Health:

```text
GET /api/health
```

Telegram webhook:

```text
POST /api/telegram/message
Header: x-telegram-webhook-secret
```

Active locations:

```text
GET /api/locations/active
```

Nearby locations:

```text
GET /api/locations/nearby?lat=41.01&lng=29.01&radius=5000
```

Archive:

```text
GET /api/locations/archive
```

Route calculation:

```text
POST /api/routes/calculate
```

Route endpoint Google Routes API kullanacak sekilde hazirlandi. `motorcycle` modunda `TWO_WHEELER`, uygun olmazsa `DRIVE` fallback mantigi var.

## Database

Prisma schema eklendi:

- `User`
- `TelegramMessage`
- `ActiveLocation`
- `LocationArchive`
- `LocationReport`

PostGIS extension:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Migration:

```text
backend/prisma/migrations/202606160001_init/migration.sql
```

Production container backend baslarken:

```bash
npx prisma migrate deploy
```

calistiriyor.

## Worker

Worker process:

```text
backend/src/worker.ts
```

Calistirdigi isler:

- BullMQ `telegram-messages` queue processor
- Telegram mesajini DB'den yukleme
- Mesaj temizleme
- Google Geocoding
- Confidence hesaplama
- `active_locations` kaydi olusturma
- `geom` PostGIS point update
- Expiration cron

Expiration:

- Her 1 dakikada calisir
- `expires_at <= now()` olan aktif lokasyonlari `location_archive` tablosuna tasir
- Aktif tablodan siler

## Message Cleaning

Dosya:

```text
backend/src/workers/message-cleaning.service.ts
```

Yapilan temizleme:

- Emoji ve sembolleri temizleme
- Gereksiz kelimeleri cikarma:
  - `sivil trafik`
  - `trafik`
  - `polis`
  - `cevirme`
  - `kontrol`
  - `ekip`
  - `dendi`
  - `var`
  - `goruldu`
- Turkish locale uppercase normalize

Eklenen skip filtreleri:

- `temiz`
- `teyit`
- `devam mi`
- `bos bildirim`
- `olmayan yer`
- `adam atmay`
- `ilgilen`

Amac:

- Temiz/teyit/admin/sohbet mesajlarini yanlislikla aktif lokasyon olarak yayinlamamak.

Ornek:

```text
PERPA DARULACEZE ONU SIVIL TRAFIK DENDI
```

islenir.

```text
Citycenter temiz
```

skip edilir.

## Telegram Listener

Dosya:

```text
telegram-listener/telegram_listener.py
```

Teknoloji:

```text
Python
Telethon
httpx
python-dotenv
```

Hedef grup:

```text
SADECE SIVIL TRAFIK
TELEGRAM_TARGET_GROUP_ID=-1003848956922
```

Not:

- Ilk basta Telethon `events.NewMessage(chats=...)` filtresi hedef gruptaki mesajlari beklenen sekilde yakalamadi.
- Bunun icin listener daha saglam hale getirildi:
  - Tum `NewMessage` event'lerini dinler
  - Iceride target group kontrolu yapar
  - Ek olarak polling fallback kullanir

Polling fallback:

- Baslangicta son 20 mesaji "seen" sayar
- Her 10 saniyede son 10 mesaji kontrol eder
- Yeni text mesajlari backend webhook'a yollar

Basarili log ornegi:

```text
Forwarding target message 45149 from poll ...
HTTP/1.1 201 Created
Forwarded Telegram message 45149
```

Bu goruldu. Yani:

```text
Telegram listener -> Backend webhook
```

calisiyor.

## Deployment

Sunucu:

```text
46.101.231.239
Ubuntu 22.04
```

Domain yok. Bu yuzden Caddy/HTTPS profili su an kullanilmiyor.

3000 portu baska projede dolu oldugu icin bu proje:

```text
BACKEND_PORT=3010
```

ile calisiyor.

Production compose:

```text
docker-compose.prod.yml
```

Compose project name:

```text
location-alert
```

Bu sayede sunucudaki diger projelerden izole.

Servisler:

- `postgres`
- `redis`
- `backend`
- `worker`
- `telegram-listener`
- `caddy` domain profile ile opsiyonel

Baslatma komutu:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production up -d --build
```

Belirli servis rebuild:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production up -d --build worker
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production up -d --build telegram-listener
```

Servis kontrol:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production ps
```

Loglar:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production logs -f telegram-listener worker backend
```

Health:

```bash
curl http://localhost:3010/api/health
```

Aktif lokasyon:

```bash
curl http://localhost:3010/api/locations/active
```

## Environment

Gercek `.env` dosyalari GitHub'a gitmemeli.

Gitignore kapsami:

- `backend/.env`
- `telegram-listener/.env`
- `.env.production`
- `telegram-listener/*.session`
- `node_modules`
- `dist`

Production env ornegi:

```text
.env.production.example
```

Sunucuda gercek dosya:

```text
.env.production
```

Kullanilan env alanlari:

```env
API_DOMAIN=unused.local
BACKEND_PORT=3010

POSTGRES_PASSWORD=<secret>
JWT_SECRET=<secret>
TELEGRAM_WEBHOOK_SECRET=<secret>

GOOGLE_MAPS_API_KEY=<secret>

TELEGRAM_API_ID=<telegram-api-id>
TELEGRAM_API_HASH=<telegram-api-hash>
TELEGRAM_TARGET_GROUP_ID=-1003848956922
```

Guvenlik notu:

- Google Maps API key, Telegram API hash ve webhook secret sohbet icinde gorundu.
- Production oncesi bunlari rotate etmek iyi olur.
- Google key mutlaka IP restriction ile `46.101.231.239` adresine ve sadece gerekli API'lere sinirlanmali:
  - Geocoding API
  - Places API
  - Routes API

## Sunucuda Son Bilinen Durum

Servisler ayaktaydi:

```text
backend: up, 3010 -> 3000
postgres: healthy
redis: healthy
telegram-listener: up
worker: up
```

Health basarili:

```json
{"status":"ok","service":"location-alert-backend","timestamp":"..."}
```

Aktif lokasyon endpoint basarili dondu.

Gorulen basarili test kaydi:

```text
PERPA DARULACEZE ONU
```

Google bunu koordinata cevirdi ve `active_locations` listesinde gorundu.

## Bilinen Eski Yanlis Kayitlar

Filtre eklenmeden once bazi yanlis aktif lokasyonlar olustu:

- `DOGA KOLEJI TEMIZ 3 ARAC BAGLANDI`
- `ADEN TESIS DEVAM MI CAGRI ALTINSEHIRDEN ADENE`
- `BU BOS BILDIRIMLERLE...`

Bunlar filtre oncesi olustugu icin yeni filtre bunlari otomatik silmez.

Istenirse DB'den silinebilir. Daha once onerilen komut:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production exec postgres \
  psql -U location_user -d location_app \
  -c "DELETE FROM active_locations WHERE id IN ('fa004314-d85f-4c55-b783-52ec5b56cc7a','ec3506b7-4874-4969-bd2f-541503eb089e','0bd84671-8fa4-4583-aead-47799b7bb6a4');"
```

Not: Bu ID'ler mevcut kayitlar hala duruyorsa gecerlidir. Silmeden once `curl /api/locations/active` ile tekrar kontrol etmek iyi olur.

## Manuel Webhook Testi

Sunucuda JSON dosyasi ile test:

```bash
cat > /tmp/test-message.json <<'JSON'
{
  "telegram_message_id": 999101,
  "telegram_group_id": -1003848956922,
  "sender_id": 12345,
  "raw_text": "PERPA DARULACEZE ONU SIVIL TRAFIK DENDI",
  "received_at": "2026-06-16T09:40:00Z"
}
JSON
```

Sonra:

```bash
curl -i -X POST http://localhost:3010/api/telegram/message \
  -H "Content-Type: application/json" \
  -H "x-telegram-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>" \
  --data-binary @/tmp/test-message.json
```

Basarili cevap:

```json
{"success":true,"message_id":"...","queued":true}
```

Sonra:

```bash
curl http://localhost:3010/api/locations/active
```

## Onemli Hatalar ve Cozumler

### Docker build Prisma type hatasi

Sunucuda build once su hata verdi:

```text
Parameter implicitly has an any type
Property 'sql' does not exist on type 'typeof Prisma'
```

Sebep:

- Docker build icinde `prisma generate` calismadan TypeScript build yapiliyordu.

Cozum:

- `backend/Dockerfile` icine `npx prisma generate` eklendi.

### Runtime Prisma Client init hatasi

Hata:

```text
@prisma/client did not initialize yet. Please run "prisma generate"
```

Cozum:

- Prisma Client dependency stage'de generate edildi
- Runtime'a generated `node_modules` tasindi
- Alpine imajina `openssl` kuruldu

### Telegram webhook 400 Bad Request

Hata:

```text
telegram_message_id must be an integer number
telegram_group_id must be an integer number
```

Cozum:

- DTO `BigInt` transform yerine HTTP tarafinda `number` validation kullanacak hale getirildi
- Prisma yazarken `BigInt(...)` cevriliyor

### Telegram NewMessage event gelmiyor

Belirti:

- Telethon update farklarini goruyordu
- Ama `Forwarded Telegram message` logu yoktu

Cozum:

- `events.NewMessage` genel dinleme
- Iceride hedef grup filtreleme
- Polling fallback

## Git / Push Notlari

GitHub repo:

```text
https://github.com/thegurluk/tag.git
```

Sunucuda proje dizini:

```text
~/apps/location-alert
```

Sunucuda update:

```bash
cd ~/apps/location-alert
git pull
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production up -d --build <service>
```

Tum servisleri rebuild:

```bash
docker compose -p location-alert -f docker-compose.prod.yml --env-file .env.production up -d --build
```

## Siradaki Isler

### 1. Backend Monitoring / Kalite

- Yeni gelen grup mesajlarini 10-15 dakika izlemek
- Yanlis lokasyon ureten metinleri tespit etmek
- Cleaning/skip kurallarini daha da iyilestirmek
- Gerekirse pending review status mantigini genisletmek

### 2. Eski Yanlis Aktif Kayitlari Temizleme

- `active_locations` listesinde filtre oncesi yanlis kayitlar varsa sil
- Sadece gercek lokasyon alertleri kalsin

### 3. Mobil App Baslangici

Planlanan stack:

```text
Flutter
Riverpod
google_maps_flutter
dio
location/geolocator
```

Ilk mobil MVP:

- Flutter app scaffold
- API base URL:

```text
http://46.101.231.239:3010/api
```

- Map screen
- Current location permission
- `GET /locations/active`
- Marker render
- Marker color:
  - red
  - yellow
  - blue
- Marker detail bottom sheet

Not:

- Domain/HTTPS olmadigi icin Android cleartext HTTP ayari gerekebilir.
- iOS tarafinda ATS exception gerekebilir.
- Production'a cikmadan once domain + HTTPS onerilir.

### 4. Route Feature

Backend endpoint hazir:

```text
POST /api/routes/calculate
```

Mobilde:

- Current location -> selected marker
- Standard / Motorcycle selector
- Polyline draw

### 5. Production Hardening

- Domain alininca Caddy profile'i aktif edilebilir
- HTTPS
- Secret rotation
- Google key restriction
- DB backup
- Basic rate limiting
- Admin/pending review paneli

## Yeni Chat Icin Kisa Baslangic Mesaji

Yeni chatte soyle baslanabilir:

```text
Bu projede HANDOFF.md dosyasini oku. Backend/Telegram/Worker sunucuda calisiyor.
Sıradaki is mobil Flutter app MVP: active locations endpointinden markerlari cekip Google Maps uzerinde gostermek.
Once mevcut repo yapisini oku, sonra mobile klasorunu olustur ve Flutter app'e basla.
```
