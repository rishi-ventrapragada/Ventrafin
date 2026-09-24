#!/usr/bin/env node
// Runs the pgTAP tests in supabase/tests against a Postgres database — no Docker needed.
//
//   Hosted:  $env:SUPABASE_DB_URL = "postgresql://postgres.<ref>:<db-password>@<pooler-host>:5432/postgres"
//            npm run db:test
//   Local:   npm run db:test            (defaults to the local Supabase stack on :54322)
//   Subset:  npm run db:test -- 02_rls_isolation
//
// Each test file wraps itself in BEGIN ... ROLLBACK, so nothing it creates
// (test users, rows, even the pgtap extension) is left behind. Rolled-back
// changes are never streamed by Realtime.
//
// The connection string contains your database password: keep it in an
// environment variable for the current terminal only. Never put it in a file.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const testsDir = path.join(root, 'supabase', 'tests');
const dbUrl = process.env.SUPABASE_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

const host = new URL(dbUrl).hostname;
const isLocal = ['127.0.0.1', 'localhost', '::1'].includes(host);

const filters = process.argv.slice(2);
const files = fs
  .readdirSync(testsDir)
  .filter((f) => f.endsWith('.test.sql'))
  .filter((f) => filters.length === 0 || filters.some((x) => f.includes(x)))
  .sort();

if (files.length === 0) {
  console.error(`No test files matched in ${testsDir}`);
  process.exit(1);
}

console.log(`Running ${files.length} test file(s) against ${host}${isLocal ? ' (local)' : ''}\n`);

let failedFiles = 0;
let totalOk = 0;
let totalNotOk = 0;

for (const file of files) {
  const sql = fs.readFileSync(path.join(testsDir, file), 'utf8');
  const client = new pg.Client({
    connectionString: dbUrl,
    // Supabase requires TLS; the pooler certificate is not in Node's default CA store.
    ssl: isLocal ? false : { rejectUnauthorized: false },
  });

  const lines = [];
  let error = null;
  try {
    await client.connect();
    const results = await client.query(sql);
    for (const r of [results].flat()) {
      for (const row of r.rows ?? []) {
        const value = Object.values(row)[0];
        // Keep TAP output only (plan, ok/not ok, # diagnostics); skip helper SELECTs.
        if (typeof value === 'string') lines.push(...value.split('\n').filter((l) => /^(ok |not ok |1\.\.|#)/.test(l)));
      }
    }
  } catch (e) {
    error = e;
    await client.query('rollback').catch(() => {});
  } finally {
    await client.end().catch(() => {});
  }

  const planned = Number(lines.find((l) => /^1\.\.\d+$/.test(l))?.slice(3) ?? NaN);
  const ok = lines.filter((l) => /^ok \d+/.test(l)).length;
  const notOk = lines.filter((l) => /^not ok \d+/.test(l)).length;
  const passed = !error && notOk === 0 && ok === planned;

  totalOk += ok;
  totalNotOk += notOk;
  if (!passed) failedFiles++;

  console.log(`${passed ? 'PASS' : 'FAIL'}  ${file}  (${ok}/${Number.isNaN(planned) ? '?' : planned})`);
  for (const l of lines) {
    if (!passed || /^not ok/.test(l)) console.log(`      ${l}`);
  }
  if (error) console.log(`      ERROR ${error.code ?? ''} ${error.message}`);
}

console.log(`\n${totalOk} passed, ${totalNotOk} failed, ${failedFiles} file(s) with problems`);
process.exit(failedFiles === 0 ? 0 : 1);
