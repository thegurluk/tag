FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY telegram_listener.py .

ENV TELEGRAM_SESSION_PATH=/app/session/telegram_session

CMD ["python", "telegram_listener.py"]
