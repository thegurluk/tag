# Real-Time Location Alert & Navigation App

Monorepo for the Telegram collector, NestJS backend, and Flutter mobile app described in `plan.md`.

## Apps

- `backend`: NestJS API, Prisma, BullMQ workers, PostgreSQL/PostGIS, Redis.
- `telegram-listener`: Python Telethon listener that forwards Telegram messages to the backend.
- `mobile`: Flutter application placeholder. The mobile app will be added after the backend MVP flow is stable.

## MVP Build Order

1. Backend base setup
2. Docker Compose with PostgreSQL/PostGIS and Redis
3. Prisma schema
4. Telegram message endpoint
5. BullMQ queue and worker
6. Message cleaning and geocoding services
7. Active location API and expiration worker
8. Telegram listener
9. Flutter map app

## Safety Positioning

This project should be presented as a community road awareness and navigation support tool. Avoid product copy that frames it as bypassing enforcement or public safety operations.
