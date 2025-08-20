import { PrismaClient } from '@prisma/client';
import nacl from 'tweetnacl';
import bs58 from 'bs58';

const prisma = new PrismaClient();

function generateWalletAddress(): string {
  const kp = nacl.sign.keyPair();
  return bs58.encode(kp.publicKey);
}

function randomChoice<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

function generateName(): string {
  const first = ['John','Jane','Alex','Sarah','Michael','Emily','Daniel','Olivia','David','Sophia','Liam','Emma','Noah','Ava','Mason','Isabella','Ethan','Mia','Logan','Amelia'];
  const last = ['Johnson','Williams','Brown','Jones','Miller','Davis','Garcia','Rodriguez','Wilson','Martinez','Anderson','Taylor','Thomas','Hernandez','Moore','Martin','Jackson','Thompson'];
  return `${randomChoice(first)} ${randomChoice(last)}`;
}

function generateDept(): string {
  const depts = ['Computer Science','Business Admin','Engineering','Mathematics','Physics','Economics','Biology','Chemistry','History','English'];
  return randomChoice(depts);
}

function generateMatric(seed: number, year = 2021): string {
  const serial = String(1000 + seed).padStart(4, '0');
  return `DE.${year}/${serial}`;
}

async function main() {
  const totalVoters = Number(process.env.SEED_VOTERS || process.argv[2] || 50);
  const adminWallet = (process.env.ADMIN_WALLET || process.env.ADMIN_WALLETS || '').split(',').map(s=>s.trim()).filter(Boolean)[0] || generateWalletAddress();

  console.log(`Seeding database... voters=${totalVoters}, adminWallet=${adminWallet}`);

  // Ensure admin user exists and has ADMIN role
  const adminUser = await prisma.user.upsert({
    where: { walletAddress: adminWallet },
    update: { role: 'ADMIN' as any },
    create: { walletAddress: adminWallet, role: 'ADMIN' as any }
  });

  // Create voters (idempotent by unique matric)
  const voters: any[] = [];
  for (let i = 0; i < totalVoters; i++) {
    const name = generateName();
    const dept = generateDept();
    const matric = generateMatric(i);
    const email = `${name.toLowerCase().replace(/\s+/g,'\.')}@university.edu`;
    voters.push({ name, department: dept, matric, email, eligible: true });
  }

  // Insert in batches
  const chunkSize = 100;
  let created = 0;
  for (let i = 0; i < voters.length; i += chunkSize) {
    const chunk = voters.slice(i, i + chunkSize);
    const res = await prisma.voter.createMany({ data: chunk, skipDuplicates: true });
    created += res.count;
  }

  // Echo a convenience voter matching the admin wallet (optional, not unique)
  try {
    const adminMatric = generateMatric(0);
    await prisma.voter.upsert({
      where: { matric: adminMatric },
      update: { walletAddress: adminWallet, walletVerified: true, walletVerifiedAt: new Date() },
      create: { name: 'Admin User', matric: adminMatric, email: 'admin@university.edu', department: 'Administration', eligible: true, walletAddress: adminWallet, walletVerified: true, walletVerifiedAt: new Date() }
    });
  } catch {}

  console.log(`Admin user: ${adminUser.walletAddress}`);
  console.log(`Voters created: ${created}/${totalVoters} (skipDuplicates applied)`);
  console.log('Done.');
}

main()
  .catch((e) => { console.error(e); process.exitCode = 1; })
  .finally(async () => { await prisma.$disconnect(); });


