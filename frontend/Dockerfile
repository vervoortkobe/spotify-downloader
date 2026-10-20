FROM oven/bun:latest

WORKDIR /app

# NEXT_PUBLIC variables are embedded into the client bundle at build time.
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_SPOTTERFY_API_KEY
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
ENV NEXT_PUBLIC_SPOTTERFY_API_KEY=${NEXT_PUBLIC_SPOTTERFY_API_KEY}

COPY package.json bun.lockb* ./
RUN bun install

COPY . .

RUN bun run build

EXPOSE 3001

CMD ["bun", "start"]
