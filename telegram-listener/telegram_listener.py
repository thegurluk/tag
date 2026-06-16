import argparse
import asyncio
import logging
import os
from datetime import timezone
from typing import Any

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

    target_raw_id = abs(target_group_id)
    if str(target_raw_id).startswith("100"):
        target_raw_id = int(str(target_raw_id)[3:])

    def is_target_event(event) -> bool:
        if event.chat_id in {target_group_id, target_raw_id}:
            return True

        peer = event.message.peer_id
        channel_id = getattr(peer, "channel_id", None)
        chat_id = getattr(peer, "chat_id", None)
        user_id = getattr(peer, "user_id", None)

        return target_raw_id in {channel_id, chat_id, user_id}

    async def forward_message(message: Any, chat_id: int, source: str) -> None:
        text = message.message
        if not text:
            logger.info("Ignored target message %s from %s because it has no text", message.id, source)
            return

        if message.id in sent_message_ids:
            return
        sent_message_ids.add(message.id)

        received_at = message.date
        if received_at.tzinfo is None:
            received_at = received_at.replace(tzinfo=timezone.utc)

        payload = {
            "telegram_message_id": message.id,
            "telegram_group_id": target_group_id,
            "sender_id": getattr(message, "sender_id", None),
            "raw_text": text,
            "received_at": received_at.astimezone(timezone.utc).isoformat(),
        }

        try:
            logger.info(
                "Forwarding target message %s from %s chat_id=%s raw=%s",
                message.id,
                source,
                chat_id,
                text[:120],
            )
            await send_to_backend(payload, backend_url, webhook_secret)
            logger.info("Forwarded Telegram message %s", message.id)
        except Exception:
            sent_message_ids.discard(message.id)
            logger.exception("Failed to forward Telegram message %s", message.id)

    @client.on(events.NewMessage)
    async def handler(event):
        if not is_target_event(event):
            return

        await forward_message(event.message, event.chat_id, "event")

    async def poll_target_messages() -> None:
        target_entity = await client.get_entity(target_group_id)
        logger.info("Polling fallback enabled for target group %s", target_group_id)

        initial_messages = [
            message async for message in client.iter_messages(target_entity, limit=20)
        ]
        for message in initial_messages:
            sent_message_ids.add(message.id)
        logger.info("Marked %s existing target messages as already seen", len(initial_messages))

        while True:
            try:
                messages = [
                    message async for message in client.iter_messages(target_entity, limit=10)
                ]
                for message in reversed(messages):
                    await forward_message(message, target_group_id, "poll")
            except Exception:
                logger.exception("Polling target messages failed")

            await asyncio.sleep(10)

    logger.info("Listening to Telegram group %s", target_group_id)
    asyncio.create_task(poll_target_messages())
    await client.run_until_disconnected()


if __name__ == "__main__":
    asyncio.run(main())
