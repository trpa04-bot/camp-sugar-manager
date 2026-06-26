#!/usr/bin/env node

const readline = require('node:readline/promises');
const {stdin: input, stdout: output} = require('node:process');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    return require('../functions/node_modules/firebase-admin');
  }
}

async function readEmailFromPrompt() {
  const rl = readline.createInterface({input, output});
  try {
    const email = (await rl.question('Unesi email korisnika: ')).trim();
    return email;
  } finally {
    rl.close();
  }
}

async function main() {
  const admin = loadFirebaseAdmin();
  const emailArg = (process.argv[2] || '').trim();
  const email = emailArg || (await readEmailFromPrompt());
  const projectId = (process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || 'camp-sugar-manager').trim();

  if (!email) {
    throw new Error('Email je obavezan. Pokreni: node scripts/set_admin_claim.js <email>');
  }

  if (!admin.apps.length) {
    admin.initializeApp({projectId});
  }

  const auth = admin.auth();
  const user = await auth.getUserByEmail(email);
  const existingClaims = user.customClaims || {};
  const hadAdmin = existingClaims.admin === true;

  console.log('Korisnik pronađen:');
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${user.email || ''}`);
  console.log(`ima claimove: ${Object.keys(existingClaims).length > 0}`);
  console.log(`admin prije: ${hadAdmin}`);

  if (!hadAdmin) {
    await auth.setCustomUserClaims(user.uid, {
      ...existingClaims,
      admin: true,
    });
  }

  const updatedUser = await auth.getUser(user.uid);
  const updatedClaims = updatedUser.customClaims || {};
  const hasAdminNow = updatedClaims.admin === true;

  console.log(`admin sada: ${hasAdminNow}`);
}

main().catch((error) => {
  console.error('Neuspjeh pri postavljanju admin claima.');
  console.error(String(error && error.message ? error.message : error));
  process.exitCode = 1;
});
