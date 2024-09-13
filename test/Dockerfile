# Use Ubuntu as the base image
FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install basic utilities
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y \
    python3.10 \
    python3.10-distutils \
    iproute2 \
    iptables \
    net-tools \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as the default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Ensure add-apt-repository works with Python 3.10
RUN apt-get update && apt-get install -y python3-apt

# Copy the script into the container
COPY test.sh /app/test.sh

# Make the script executable
RUN chmod +x /app/test.sh

# Set the working directory
WORKDIR /app

# Run the script when the container launches
CMD ["/bin/bash", "/app/test.sh"]