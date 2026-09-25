// One-time setup for the weekly backup (supabase/BACKUPS.md, DECISIONS.md D27).
//
// Prints, to this terminal only (nothing is written to disk or sent anywhere):
//   1. BACKUP_DB_URL      the connection string for the read-only
//                         `ventrafin_backup` role, for a GitHub Actions secret
//   2. BACKUP_PASSPHRASE  the key the backups are encrypted with, for a GitHub
//                         Actions secret AND your password manager
//   3. an ALTER ROLE statement to run once in the Supabase SQL editor. It sets
//      the role's password as a SCRAM-SHA-256 verifier (a salted hash), so the
//      password itself never appears in the dashboard's query history or the
//      database logs.
//
// Usage (from the repo root; Node 22+, no packages needed):
//   node scripts/backup-credentials.mjs "<Session pooler connection string>"
// Copy the string from the Supabase dashboard: Connect > Connection string >
// Method: Session pooler. It looks like
//   postgresql://postgres.<ref>:[YOUR-PASSWORD]@aws-1-<region>.pooler.supabase.com:5432/postgres
// The [YOUR-PASSWORD] part is ignored; you don't need the database password.
//
//   node scripts/backup-credentials.mjs --self-test   checks the SCRAM code against RFC 7677
import { createHash, createHmac, pbkdf2Sync, randomBytes, randomInt } from 'node:crypto'

const ROLE = 'ventrafin_backup'
const ITERATIONS = 4096 // Postgres's default for SCRAM-SHA-256

/** Random text from letters and digits only, so it needs no escaping in a URL or in SQL. */
function randomText(length) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  return Array.from({ length }, () => alphabet[randomInt(alphabet.length)]).join('')
}

function hmac(key, text) {
  return createHmac('sha256', key).update(text).digest()
}

/** The keys Postgres stores for a SCRAM-SHA-256 password (RFC 5802 / 7677). */
function scramKeys(password, salt, iterations) {
  const salted = pbkdf2Sync(Buffer.from(password, 'utf8'), salt, iterations, 32, 'sha256')
  const clientKey = hmac(salted, 'Client Key')
  return { clientKey, storedKey: createHash('sha256').update(clientKey).digest(), serverKey: hmac(salted, 'Server Key') }
}

/** Postgres's text form: SCRAM-SHA-256$<iterations>:<salt>$<StoredKey>:<ServerKey> (base64). */
function scramVerifier(password) {
  const salt = randomBytes(16)
  const { storedKey, serverKey } = scramKeys(password, salt, ITERATIONS)
  return `SCRAM-SHA-256$${ITERATIONS}:${salt.toString('base64')}$${storedKey.toString('base64')}:${serverKey.toString('base64')}`
}

/** The example exchange in RFC 7677 § 3: both the client proof and the server signature must match. */
function selfTest() {
  const salt = Buffer.from('W22ZaJ0SNY7soEsUEjb6gQ==', 'base64')
  const { clientKey, storedKey, serverKey } = scramKeys('pencil', salt, 4096)
  const authMessage =
    'n=user,r=rOprNGfwEbeRWgbNEkqO,' +
    'r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096,' +
    'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0'
  const signature = hmac(storedKey, authMessage)
  const proof = Buffer.from(clientKey.map((b, i) => b ^ signature[i])).toString('base64')
  const serverSignature = hmac(serverKey, authMessage).toString('base64')
  const ok = proof === 'dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=' && serverSignature === '6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4='
  console.log(ok ? 'SCRAM self-test passed (RFC 7677 example).' : 'SCRAM self-test FAILED.')
  process.exit(ok ? 0 : 1)
}

if (process.argv[2] === '--self-test') selfTest()

const pooler = process.argv[2]
const match = pooler && /^postgres(?:ql)?:\/\/postgres\.([a-z0-9]+)(?::[^@]*)?@([^/:]+\.pooler\.supabase\.com):(\d+)\/(\w+)/.exec(pooler.trim())
if (!match) {
  console.error(
    'Pass the Session pooler connection string from the Supabase dashboard (Connect > Connection string > Session pooler), e.g.\n' +
      '  node scripts/backup-credentials.mjs "postgresql://postgres.<ref>:[YOUR-PASSWORD]@aws-1-<region>.pooler.supabase.com:5432/postgres"',
  )
  process.exit(1)
}
const [, ref, host, port, database] = match
if (port !== '5432') {
  console.error(`Use the Session pooler (port 5432), not the Transaction pooler (port ${port}): pg_dump needs a session.`)
  process.exit(1)
}

const password = randomText(40)
const passphrase = randomText(48)

console.log(`
=== 1. Run this once in the Supabase SQL editor (project ${ref}) ===

alter role ${ROLE} with login password '${scramVerifier(password)}';

(It stores a salted hash; the password below is not in it. LOGIN is switched
off while backups are off, so this also lets the role log in again.)

=== 2. GitHub: repo > Settings > Secrets and variables > Actions > New repository secret ===

Name:  BACKUP_DB_URL
Value: postgresql://${ROLE}.${ref}:${password}@${host}:${port}/${database}?sslmode=require

Name:  BACKUP_PASSPHRASE
Value: ${passphrase}

=== 3. Save BACKUP_PASSPHRASE in your password manager as well ===

GitHub never shows a secret again. Without this passphrase the backups cannot be
decrypted, so a copy outside GitHub is what makes them restorable.

Then clear this terminal (cls / clear).
`)
