FROM python:3.11-slim

# Install ffmpeg and Node.js for yt-dlp (audio extraction + JS runtime)
RUN apt-get update && \
    apt-get install -y ffmpeg nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire root project so spotifydown_api.py is available
COPY . .

WORKDIR /app/web-app/sunnify-backend

# Upgrade pip and install latest yt-dlp for reliable downloads
RUN pip install --no-cache-dir --upgrade pip yt-dlp && \
    pip install --no-cache-dir -r requirements.txt

EXPOSE 5000

ENV PYTHONPATH=/app
CMD ["python", "app.py"]
