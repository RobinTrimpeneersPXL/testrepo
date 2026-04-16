FROM ubuntu:latest

# Stress test build: Install many packages and perform a long-running task
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libboost-all-dev \
    python3 \
    python3-pip \
    wget \
    curl \
    vim \
    htop \
    ffmpeg \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Simulate heavy workload
RUN dd if=/dev/urandom of=largefile bs=1M count=100
RUN sha256sum largefile
RUN rm largefile

CMD ["/bin/bash"]
