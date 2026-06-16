# Backend

NestJS API for the real-time community road alert MVP.

## Setup

```powershell
npm install
Copy-Item .env.example .env
```

Fill `.env`, then start PostgreSQL/PostGIS and Redis. With Docker installed:

```powershell
docker compose up -d
```

Generate Prisma client and run migrations:

```powershell
npx prisma generate
npx prisma migrate dev --name init
```

Run the API:

```powershell
npm run start:dev
```

Health check:

```text
GET http://localhost:3000/api/health
```

## Telegram Webhook

```text
POST /api/telegram/message
Header: x-telegram-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
```

The endpoint stores the raw Telegram message and queues it for processing.

## Worker Behavior

The API process currently includes:

- BullMQ Telegram message processor
- Message cleaning
- Google geocoding lookup
- Active location creation
- One-minute expiration job that moves expired locations to archive

For a separate worker process:

```powershell
npm run worker:dev
```

In production, run either API-with-workers or split API and worker processes, but avoid running duplicate workers unless that is intentional.

## Current External Requirements

- PostgreSQL with PostGIS
- Redis
- Google Maps API key with Geocoding and Routes APIs enabled
- Telegram webhook secret shared with `telegram-listener`
