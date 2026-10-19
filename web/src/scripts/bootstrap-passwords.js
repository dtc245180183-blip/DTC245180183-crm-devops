const bcrypt = require('bcrypt');
const db = require('../db');

async function bootstrapPasswords() {
  try {
    const res = await db.query("SELECT id, username, role FROM users WHERE password_hash = '!PENDING'");
    if (res.rows.length === 0) {
      console.log('[Bootstrap] No users with password_hash = "!PENDING". Skipping password bootstrap.');
      return;
    }

    console.log(`[Bootstrap] Found ${res.rows.length} pending user(s). Updating bcrypt hashes...`);

    const mgrPass = process.env.SEED_MANAGER_PASSWORD || 'Admin@1234567890';
    const salesPass = process.env.SEED_SALES_PASSWORD || 'Sales@1234567890';
    const supportPass = process.env.SEED_SUPPORT_PASSWORD || 'Support@1234567890';

    const [mgrHash, salesHash, supportHash] = await Promise.all([
      bcrypt.hash(mgrPass, 10),
      bcrypt.hash(salesPass, 10),
      bcrypt.hash(supportPass, 10),
    ]);

    for (const user of res.rows) {
      let targetHash = salesHash;
      if (user.role === 'manager') targetHash = mgrHash;
      else if (user.role === 'support') targetHash = supportHash;

      await db.query('UPDATE users SET password_hash = $1 WHERE id = $2', [targetHash, user.id]);
      console.log(`[Bootstrap] Updated password hash for user '${user.username}' (role: ${user.role})`);
    }

    console.log('[Bootstrap] Password bootstrapping completed successfully.');
  } catch (err) {
    console.error('[Bootstrap] Error during password bootstrap:', err.message);
    throw err;
  }
}

module.exports = bootstrapPasswords;
