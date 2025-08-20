param(
  [int]$Voters = 50,
  [string]$AdminWallet = ""
)

Write-Host "Seeding Mac Votes database inside Docker..." -ForegroundColor Cyan

$envArgs = @()
if ($AdminWallet -ne "") { $envArgs += "-e", "ADMIN_WALLET=$AdminWallet" }
$envArgs += "-e", "SEED_VOTERS=$Voters"

docker compose -f ./docker-compose.simple.yml up -d postgres | Out-Null
Start-Sleep -Seconds 2

docker compose -f ./docker-compose.simple.yml up -d --build api | Out-Null

Write-Host "Running seed..." -ForegroundColor Cyan
docker exec -e SEED_VOTERS=$Voters `
    $(if ($AdminWallet -ne "") { "-e ADMIN_WALLET=$AdminWallet" }) `
    mac-votes-api sh -lc "npm run seed" | Write-Output

Write-Host "Seed completed." -ForegroundColor Green

