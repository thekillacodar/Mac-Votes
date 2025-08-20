FROM node:20-bullseye-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm i

COPY . .
RUN npm run build

EXPOSE 8080
CMD ["sh", "-c", "npx prisma db push --accept-data-loss && node dist/index.js"]


