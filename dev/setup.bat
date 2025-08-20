@echo off
echo 🚀 Setting up Mac Votes Solana Development Environment...

REM Check if Docker is installed
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Docker is not installed. Please install Docker Desktop first.
    pause
    exit /b 1
)

REM Check if Docker Compose is installed
docker-compose --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Docker Compose is not installed. Please install Docker Compose first.
    pause
    exit /b 1
)

echo ✅ Docker and Docker Compose are installed

REM Create necessary directories
echo 📁 Creating project directories...
if not exist "frontend" mkdir frontend
if not exist "backend" mkdir backend
if not exist "programs" mkdir programs
if not exist "database" mkdir database
if not exist "scripts" mkdir scripts

REM Build and start Docker containers
echo 🐳 Building and starting Docker containers...
docker-compose build
if %errorlevel% neq 0 (
    echo ❌ Failed to build Docker containers
    pause
    exit /b 1
)

docker-compose up -d
if %errorlevel% neq 0 (
    echo ❌ Failed to start Docker containers
    pause
    exit /b 1
)

REM Wait for services to be ready
echo ⏳ Waiting for services to be ready...
timeout /t 15 /nobreak >nul

REM Check if containers are running
echo 🔍 Checking container status...
docker-compose ps

REM Wait for solana-dev container to be ready
echo ⏳ Waiting for development container to be ready...
:wait_loop
docker-compose exec -T solana-dev echo "ready" >nul 2>&1
if %errorlevel% neq 0 (
    echo Still waiting for container...
    timeout /t 5 /nobreak >nul
    goto wait_loop
)

echo ✅ Container is ready!

REM Generate Solana keypair
echo 🔑 Generating Solana keypair...
docker-compose exec -T solana-dev solana-keygen new --outfile /root/.config/solana/id.json --no-bip39-passphrase

REM Set Solana config to localhost
echo 🔧 Configuring Solana CLI...
docker-compose exec -T solana-dev solana config set --url http://localhost:8899

REM Airdrop SOL for testing
echo 💰 Airdropping SOL for testing...
docker-compose exec -T solana-dev solana airdrop 2

echo ✅ Setup complete! Your development environment is ready.
echo.
echo 📋 Next steps:
echo 1. Access the development container: docker-compose exec solana-dev bash
echo 2. Start the Solana test validator: solana-test-validator --rpc-port 8899
echo 3. Build and deploy your programs: anchor build && anchor deploy
echo 4. Start the frontend: cd frontend && npm run dev
echo 5. Start the backend: cd backend && npm run dev
echo.
echo 🌐 Services available:
echo - Frontend: http://localhost:3000
echo - Backend API: http://localhost:8080
echo - Solana RPC: http://localhost:8899
echo - Database: localhost:5432
echo - Redis: localhost:6379

pause
