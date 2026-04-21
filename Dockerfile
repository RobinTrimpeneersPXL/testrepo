FROM alpine:latest

# Lighter stress test: Install basic tools
RUN apk add --no-cache \
    build-base \
    cmake \
    git \
    python3 \
    wget \
    curl \
    vim \
    htop
CMD ["echo", "Hello from the optimized runner!"]
