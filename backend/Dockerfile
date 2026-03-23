FROM python:3.11-slim

# Install ffmpeg, deno, and prerequisites for yt-dlp
RUN apt-get update && \
    apt-get install -y ffmpeg curl unzip && \
    curl -fsSL https://deno.land/x/install/install.sh | sh && \
    rm -rf /var/lib/apt/lists/*

ENV DENO_INSTALL="/root/.deno"
ENV PATH="$DENO_INSTALL/bin:$PATH"

WORKDIR /app

# Copy the entire root project so spotifydown_api.py is available
COPY . .

WORKDIR /app/backend

# Upgrade pip and install latest yt-dlp for reliable downloads
RUN pip install --no-cache-dir --upgrade pip yt-dlp && \
    pip install --no-cache-dir -r requirements.txt

EXPOSE 5000

ENV PYTHONPATH=/app
CMD ["python", "app.py"]
