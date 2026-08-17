FROM python:3.11-slim

# Install system dependencies (ffmpeg, curl, unzip, gnupg) and Deno in one step for better caching
RUN apt-get update && \
    apt-get install -y ffmpeg curl unzip gnupg && \
    curl -fsSL https://deno.land/x/install/install.sh | sh && \
    rm -rf /var/lib/apt/lists/*

# Install Cloudflare WARP client
RUN apt-get update && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    rm -rf /var/lib/apt/lists/*

# Set Deno path
ENV DENO_INSTALL="/root/.deno"
ENV PATH="$DENO_INSTALL/bin:$PATH"

WORKDIR /app

# Copy requirements file first to take advantage of Docker layer caching
COPY requirements.txt .

# Upgrade pip and install latest yt-dlp first for reliable downloads, then install all requirements
RUN pip install --no-cache-dir --upgrade pip yt-dlp && \
    pip install --no-cache-dir -r requirements.txt

# Configure yt-dlp to use remote EJS components for JS challenge solving
# and pre-download the solver so it's cached at build time
RUN mkdir -p ~/.yt-dlp && \
    echo "--remote-components ejs:github" > ~/.yt-dlp/config && \
    deno --version

# Copy the rest of the application code
COPY . .

# Make the WARP init script executable
RUN chmod +x /app/warp-init.sh

# Expose only the required port
EXPOSE 5000

# Set Python path to ensure imports are found correctly within /app
ENV PYTHONPATH=/app

# Set WARP proxy for yt-dlp, requests, and httpx
ENV ALL_PROXY=http://127.0.0.1:4000
ENV HTTP_PROXY=http://127.0.0.1:4000
ENV HTTPS_PROXY=http://127.0.0.1:4000

# Entrypoint initializes WARP then starts the app
ENTRYPOINT ["/app/warp-init.sh"]
CMD ["python", "app.py"]
