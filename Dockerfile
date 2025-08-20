# Solana Development Environment Dockerfile
# Latest versions as of 2024-2025

FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root
ENV PATH="/root/.cargo/bin:/root/.local/share/solana/install/active_release/bin:/root/.local/share/agave/install/active_release/bin:${PATH}"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    libudev-dev \
    libclang-dev \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Rust (latest stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN . "$HOME/.cargo/env"

# Install Solana CLI (latest version 2.2.12)
RUN sh -c "$(curl -sSfL https://release.solana.com/v2.2.12/install)"

# Install Agave CLI (latest version 2.1.0) - successor to Solana CLI
RUN sh -c "$(curl -sSfL https://release.anza.xyz/v2.1.0/install)"

# Install Anchor CLI (latest version 0.31.1)
RUN cargo install --git https://github.com/coral-xyz/anchor avm --force
RUN avm install 0.31.1
RUN avm use 0.31.1

# Install Node.js dependencies for frontend development
RUN npm install -g yarn typescript ts-node

# Install latest Solana Web3.js and Wallet Adapter
RUN npm install -g @solana/web3.js@latest
RUN npm install -g @solana/wallet-adapter-base@latest
RUN npm install -g @solana/wallet-adapter-wallets@latest

# Set up working directory
WORKDIR /app

# Create directories for the project
RUN mkdir -p /app/frontend /app/backend /app/programs /app/scripts /app/database

# Expose ports
EXPOSE 3000 8080 8899 8900

# Default command
CMD ["/bin/bash"]
