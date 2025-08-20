#!/bin/bash

# Mac Votes - Solana Development Environment Setup Script
# This script sets up the complete development environment

set -e

echo "🚀 Setting up Mac Votes Solana Development Environment..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"

# Create necessary directories
echo "📁 Creating project directories..."
mkdir -p frontend backend programs database scripts

# Create database initialization script
echo "🗄️ Setting up database..."
mkdir -p database
cat > database/init.sql << 'EOF'
-- Mac Votes Database Initialization
CREATE DATABASE IF NOT EXISTS macvotes;
USE macvotes;

-- Students table
CREATE TABLE IF NOT EXISTS students (
    id SERIAL PRIMARY KEY,
    matric_number VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    department VARCHAR(100) NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Elections table
CREATE TABLE IF NOT EXISTS elections (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    level VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'draft',
    total_votes INTEGER DEFAULT 0,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Candidates table
CREATE TABLE IF NOT EXISTS candidates (
    id SERIAL PRIMARY KEY,
    election_id INTEGER REFERENCES elections(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    department VARCHAR(100) NOT NULL,
    level VARCHAR(50) NOT NULL,
    avatar VARCHAR(10) NOT NULL,
    color VARCHAR(20) NOT NULL,
    votes INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Votes table
CREATE TABLE IF NOT EXISTS votes (
    id SERIAL PRIMARY KEY,
    election_id INTEGER REFERENCES elections(id) ON DELETE CASCADE,
    candidate_id INTEGER REFERENCES candidates(id) ON DELETE CASCADE,
    voter_matric VARCHAR(20) NOT NULL,
    voter_name VARCHAR(100) NOT NULL,
    wallet_address VARCHAR(44) NOT NULL,
    transaction_id VARCHAR(64) NOT NULL,
    blockchain_signature VARCHAR(88),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default admin user
INSERT INTO students (matric_number, name, email, department, is_admin) 
VALUES ('DE.2021/0001', 'Admin User', 'admin@university.edu', 'Administration', true)
ON CONFLICT (matric_number) DO NOTHING;

-- Insert sample students
INSERT INTO students (matric_number, name, email, department) VALUES
('DE.2021/4311', 'John Doe', 'john@university.edu', 'Computer Science'),
('DE.2021/4312', 'Jane Smith', 'jane@university.edu', 'Business Admin'),
('DE.2021/4313', 'Bob Wilson', 'bob@university.edu', 'Engineering')
ON CONFLICT (matric_number) DO NOTHING;
EOF

# Create environment file
echo "⚙️ Creating environment configuration..."
cat > .env << 'EOF'
# Solana Configuration
SOLANA_RPC_URL=http://localhost:8899
SOLANA_WS_URL=ws://localhost:8900
SOLANA_NETWORK=localnet

# Database Configuration
DATABASE_URL=postgresql://macvotes_user:macvotes_password@localhost:5432/macvotes
REDIS_URL=redis://localhost:6379

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
JWT_EXPIRES_IN=24h

# Admin Configuration
ADMIN_PASSWORD=admin123

# Frontend Configuration
NEXT_PUBLIC_SOLANA_RPC_URL=http://localhost:8899
NEXT_PUBLIC_SOLANA_WS_URL=ws://localhost:8900
NEXT_PUBLIC_API_URL=http://localhost:8080
EOF

# Build and start Docker containers
echo "🐳 Building and starting Docker containers..."
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Generate Solana keypair
echo "🔑 Generating Solana keypair..."
docker-compose exec solana-dev solana-keygen new --outfile /root/.config/solana/id.json --no-bip39-passphrase

# Set Solana config to localhost
echo "🔧 Configuring Solana CLI..."
docker-compose exec solana-dev solana config set --url http://localhost:8899

# Airdrop SOL for testing
echo "💰 Airdropping SOL for testing..."
docker-compose exec solana-dev solana airdrop 2

echo "✅ Setup complete! Your development environment is ready."
echo ""
echo "📋 Next steps:"
echo "1. Access the development container: docker-compose exec solana-dev bash"
echo "2. Start the Solana test validator: solana-test-validator --rpc-port 8899"
echo "3. Build and deploy your programs: anchor build && anchor deploy"
echo "4. Start the frontend: cd frontend && npm run dev"
echo "5. Start the backend: cd backend && npm run dev"
echo ""
echo "🌐 Services available:"
echo "- Frontend: http://localhost:3000"
echo "- Backend API: http://localhost:8080"
echo "- Solana RPC: http://localhost:8899"
echo "- Database: localhost:5432"
echo "- Redis: localhost:6379"
