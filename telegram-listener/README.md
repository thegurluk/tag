# Telegram Listener

Python Telethon service that listens to a target Telegram group and forwards messages to the backend.

## Setup

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Fill `.env` with:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`
- `TELEGRAM_TARGET_GROUP_ID`
- `BACKEND_TELEGRAM_WEBHOOK_URL`
- `BACKEND_TELEGRAM_WEBHOOK_SECRET`

## First Login

```powershell
python telegram_listener.py --list-dialogs
```

Telethon will ask for your phone number, login code, and 2FA password if enabled. It creates `telegram_session.session`; never commit or expose this file.

## Run Listener

```powershell
python telegram_listener.py
```
