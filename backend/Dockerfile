FROM python:3.11-slim

# Install system dependencies (ffmpeg, curl, unzip) and Deno in one step for better caching
RUN apt-get update && \
    apt-get install -y ffmpeg curl unzip && \
    curl -fsSL https://deno.land/x/install/install.sh | sh && \
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

# Expose only the required port
EXPOSE 5000

# Set Python path to ensure imports are found correctly within /app
ENV PYTHONPATH=/app

# Command to run the application
CMD ["python", "app.py"]
