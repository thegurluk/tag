import argparse
import asyncio
import logging
import os
from datetime import timezone

import httpx
from dotenv import load_dotenv
from telethon import TelegramClient, events
from telethon.utils import get_peer_id


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("telegram-listener")


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


async def list_dialogs(client: TelegramClient) -> None:
    async for dialog in client.iter_dialogs():
        entity = dialog.entity
        entity_id = getattr(entity, "id", None)
        peer_id = get_peer_id(entity)
        logger.info(
            "Dialog: title=%s id=%s peer_id=%s",
            dialog.name,
            entity_id,
            peer_id,
        )


async def send_to_backend(payload: dict, backend_url: str, webhook_secret: str) -> None:
    headers = {"x-telegram-webhook-secret": webhook_secret}
    async with httpx.AsyncClient(timeout=10) as http:
        response = await http.post(backend_url, json=payload, headers=headers)
        if response.is_error:
            logger.error("Backend rejected message: %s", response.text)
        response.raise_for_status()


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list-dialogs", action="store_true")
    args = parser.parse_args()

    load_dotenv()

    api_id = int(require_env("TELEGRAM_API_ID"))
    api_hash = require_env("TELEGRAM_API_HASH")
    target_group_id = int(require_env("TELEGRAM_TARGET_GROUP_ID"))
    backend_url = require_env("BACKEND_TELEGRAM_WEBHOOK_URL")
    webhook_secret = require_env("BACKEND_TELEGRAM_WEBHOOK_SECRET")

    session_path = os.getenv("TELEGRAM_SESSION_PATH", "telegram_session")
    client = TelegramClient(session_path, api_id, api_hash)
    sent_message_ids: set[int] = set()

    await client.start()

    if args.list_dialogs:
        await list_dialogs(client)
        await client.disconnect()
        return

    @client.on(events.NewMessage(chats=target_group_id))
    async def handler(event):
        text = event.message.message
        if not text:
            return

        if event.message.id in sent_message_ids:
            return
        sent_message_ids.add(event.message.id)

        received_at = event.message.date
        if received_at.tzinfo is None:
            received_at = received_at.replace(tzinfo=timezone.utc)

        payload = {
            "telegram_message_id": event.message.id,
            "telegram_group_id": target_group_id,
            "sender_id": event.sender_id,
            "raw_text": text,
            "received_at": received_at.astimezone(timezone.utc).isoformat(),
        }

        try:
            await send_to_backend(payload, backend_url, webhook_secret)
            logger.info("Forwarded Telegram message %s", event.message.id)
        except Exception:
            sent_message_ids.discard(event.message.id)
            logger.exception("Failed to forward Telegram message %s", event.message.id)

    logger.info("Listening to Telegram group %s", target_group_id)
    await client.run_until_disconnected()


if __name__ == "__main__":
    asyncio.run(main())
