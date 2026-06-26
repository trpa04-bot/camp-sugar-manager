const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {doc, getDoc} = require('firebase/firestore');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    'FIRESTORE_EMULATOR_HOST is not set. Refusing to run rules tests without Firestore Emulator.'
  );
}

let testEnv;

test.before(async () => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, '../../firestore.rules'),
    'utf8'
  );

  testEnv = await initializeTestEnvironment({
    projectId: 'camp-sugar-manager-rules-test',
    firestore: {rules},
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function authDb(uid, admin) {
  const token = admin === undefined ? {} : {admin};
  return testEnv.authenticatedContext(uid, token).firestore();
}

test('unauthenticated user cannot read googleCalendarConnections', async () => {
  const db = unauthDb();
  const ref = doc(db, 'googleCalendarConnections/user-a');
  await assertFails(getDoc(ref));
});

test('authenticated non-admin cannot read own googleCalendarConnections doc', async () => {
  const db = authDb('user-a', false);
  const ref = doc(db, 'googleCalendarConnections/user-a');
  await assertFails(getDoc(ref));
});

test('authenticated admin cannot read another user googleCalendarConnections doc', async () => {
  const db = authDb('admin-user', true);
  const ref = doc(db, 'googleCalendarConnections/user-a');
  await assertFails(getDoc(ref));
});

test('authenticated admin can read own googleCalendarConnections doc', async () => {
  const db = authDb('admin-user', true);
  const ref = doc(db, 'googleCalendarConnections/admin-user');
  const snap = await assertSucceeds(getDoc(ref));
  assert.equal(snap.exists(), false);
});

test('client cannot read googleCalendarSecrets even with admin claim', async () => {
  const db = authDb('admin-user', true);
  const ref = doc(db, 'googleCalendarSecrets/admin-user');
  await assertFails(getDoc(ref));
});
