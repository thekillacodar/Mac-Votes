# Mac Votes - Solana Development Environment Setup Script (PowerShell)
# This script sets up the complete development environment on Windows

Write-Host "🚀 Setting up Mac Votes Solana Development Environment..." -ForegroundColor Green

# Check if Docker is installed
try {
    docker --version | Out-Null
    Write-Host "✅ Docker is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not installed. Please install Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Check if Docker Compose is installed
try {
    docker-compose --version | Out-Null
    Write-Host "✅ Docker Compose is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker Compose is not installed. Please install Docker Compose first." -ForegroundColor Red
    exit 1
}

# Create necessary directories
Write-Host "📁 Creating project directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path frontend, backend, programs, database, scripts | Out-Null

# Create database initialization script
Write-Host "🗄️ Setting up database..." -ForegroundColor Yellow
$initSql = @"
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
"@

$initSql | Out-File -FilePath "database/init.sql" -Encoding UTF8

# Create environment file
Write-Host "⚙️ Creating environment configuration..." -ForegroundColor Yellow
$envContent = @"
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
"@

$envContent | Out-File -FilePath ".env" -Encoding UTF8

# Build and start Docker containers
Write-Host "🐳 Building and starting Docker containers..." -ForegroundColor Yellow
try {
    docker-compose build
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build Docker containers"
    }
    
    docker-compose up -d
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start Docker containers"
    }
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}

# Wait for services to be ready
Write-Host "⏳ Waiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Check container status
Write-Host "🔍 Checking container status..." -ForegroundColor Yellow
docker-compose ps

# Wait for solana-dev container to be ready
Write-Host "⏳ Waiting for development container to be ready..." -ForegroundColor Yellow
do {
    try {
        docker-compose exec -T solana-dev echo "ready" | Out-Null
        $ready = $true
    } catch {
        Write-Host "Still waiting for container..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        $ready = $false
    }
} while (-not $ready)

Write-Host "✅ Container is ready!" -ForegroundColor Green

# Generate Solana keypair
Write-Host "🔑 Generating Solana keypair..." -ForegroundColor Yellow
docker-compose exec -T solana-dev solana-keygen new --outfile /root/.config/solana/id.json --no-bip39-passphrase

# Set Solana config to localhost
Write-Host "🔧 Configuring Solana CLI..." -ForegroundColor Yellow
docker-compose exec -T solana-dev solana config set --url http://localhost:8899

# Airdrop SOL for testing
Write-Host "💰 Airdropping SOL for testing..." -ForegroundColor Yellow
docker-compose exec -T solana-dev solana airdrop 2

Write-Host "✅ Setup complete! Your development environment is ready." -ForegroundColor Green
Write-Host ""
Write-Host "📋 Next steps:" -ForegroundColor Cyan
Write-Host "1. Access the development container: docker-compose exec solana-dev bash" -ForegroundColor White
Write-Host "2. Start the Solana test validator: solana-test-validator --rpc-port 8899" -ForegroundColor White
Write-Host "3. Build and deploy your programs: anchor build && anchor deploy" -ForegroundColor White
Write-Host "4. Start the frontend: cd frontend && npm run dev" -ForegroundColor White
Write-Host "5. Start the backend: cd backend && npm run dev" -ForegroundColor White
Write-Host ""
Write-Host "🌐 Services available:" -ForegroundColor Cyan
Write-Host "- Frontend: http://localhost:3000" -ForegroundColor White
Write-Host "- Backend API: http://localhost:8080" -ForegroundColor White
Write-Host "- Solana RPC: http://localhost:8899" -ForegroundColor White
Write-Host "- Database: localhost:5432" -ForegroundColor White
Write-Host "- Redis: localhost:6379" -ForegroundColor White
