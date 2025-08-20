# 🗳️ Mac Votes – Solana‑backed Student Voting (Dockerized)

Secure, cookie‑based web app for student elections. Votes are verified on Solana Devnet and stored in PostgreSQL for aggregation and realtime updates.

## TL;DR (Quick Start)

Prereqs: Docker Desktop (with Compose) and a browser wallet (Phantom).

```bash
# from the repo root
docker compose -f docker-compose.simple.yml up -d --build

# seed the database (optional but recommended)
powershell -ExecutionPolicy Bypass -File .\seed.ps1 -Voters 50

# open the app
# web (static UI):   http://localhost:3000
# api (backend):     http://localhost:8080/health
```

First wallet that signs in becomes ADMIN automatically, or you can provide an explicit admin wallet during seeding:

```powershell
powershell -ExecutionPolicy Bypass -File .\seed.ps1 -Voters 100 -AdminWallet {YOUR_WALLET_ADDRESS}
```

## What’s running (simple stack)

File `docker-compose.simple.yml` starts:

- Web (Nginx) → serves `index.html` on port 3000
- API (Node/Express) → port 8080
- Postgres → port 5432

You do not need the heavy Solana/Anchor dev container to run the MVP.

## App flow

1) Student enters matric → API verifies via `/api/voters/verify/:matric`.
2) Connect Phantom → app links wallet to matric (enforced: 1 wallet ⇄ 1 matric).
3) Student selects an election card → candidate grid appears.
4) Vote → a Solana memo tx is submitted, and the signature is saved to the API.
5) Realtime totals update (SSE) in the UI.

## Admin

- Click “Admin Panel”, sign a message → backend verifies and sets a secure cookie.
- Only ADMIN users can access admin endpoints; non‑admins are blocked in the UI.
- Create elections and candidates from the panel. New elections appear as cards on the voter page.

Bootstrap admin options:

- First wallet that signs in is promoted to ADMIN automatically, or
- Set env var `ADMIN_WALLETS`/`ADMIN_WALLET` on the API container, or
- Run `seed.ps1 -AdminWallet <WALLET>`.

## Commands you’ll use most

```bash
# start/stop
docker compose -f docker-compose.simple.yml up -d --build
docker compose -f docker-compose.simple.yml down

# logs
docker compose -f docker-compose.simple.yml logs -f api

# seed again (Windows PowerShell)
powershell -ExecutionPolicy Bypass -File .\seed.ps1 -Voters 50
```

## Backend (Express + Prisma)

Key endpoints (public unless noted):

- GET  `/health` → `{ ok: true }`
- GET  `/api/elections` → list active elections
- GET  `/api/elections/:id` → election with candidates
- GET  `/api/elections/active` → `{}` or the active election
- GET  `/api/stats/:electionId` → aggregated counts per candidate
- GET  `/api/stream/:electionId` → Server‑Sent Events with live totals
- GET  `/api/voters/verify/:matric` → verify matric exists & eligible
- POST `/api/voters/wallet` → link wallet to matric (409 on conflict)
- GET  `/api/votes/hasVoted?electionId&matric` → `{ ok, hasVoted }`
- POST `/auth/nonce` → request nonce for wallet sign‑in
- POST `/auth/verify` (sets cookie) → ADMIN cookie if wallet is admin

Admin‑only:

- GET  `/admin/elections`
- POST `/admin/elections` (create)
- PATCH `/admin/elections/:id/status` (ACTIVE/COMPLETED)

DB schema is in `backend/prisma/schema.prisma`. Prisma is pushed on boot (non‑destructive).

## Seeding

We ship a simple seeder that creates Voters and one ADMIN user.

```bash
# Windows PowerShell
powershell -ExecutionPolicy Bypass -File .\seed.ps1 -Voters 50
powershell -ExecutionPolicy Bypass -File .\seed.ps1 -Voters 100 -AdminWallet <YOUR_WALLET>
```

Notes:

- The seeder respects unique matric and unique wallet rules.
- One wallet can link to only one matric; one matric can link to only one wallet.

## Frontend

The UI is a single `index.html` served by Nginx:

- Elections render as cards; clicking loads candidates for that election only.
- Totals load from the API and update via SSE.
- Admin panel is gated: non‑admins cannot open it even after signing.

## Troubleshooting

- API not responding: `docker compose -f docker-compose.simple.yml logs -f api`
- DB resets on start: we disabled destructive resets by default.
- Cannot link wallet: you’ll see `409 Conflict` if the wallet is linked to another matric; choose a different wallet or matric.
- No elections visible: create one in the Admin panel, then refresh the voter page.

## Development (optional)

You can edit and rebuild just the API quickly:

```bash
docker compose -f docker-compose.simple.yml up -d --build api
```

The heavyweight Solana/Anchor dev environment in `docker-compose.yml` is provided for program development but isn’t needed for this MVP.

## License

MIT
