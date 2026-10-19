const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const db = require('../db');
const { requireAuth, requireRole } = require('../middlewares/auth');

// Toàn bộ route trong users.js chỉ dành cho manager
router.use(requireAuth, requireRole('manager'));

// 1. Danh sách nhân viên
router.get('/', async (req, res) => {
  try {
    const usersRes = await db.query(`
      SELECT id, username, email, full_name, role, is_active, created_at
      FROM users
      ORDER BY id ASC
    `);

    res.render('users/index', {
      title: 'Quản lý Tài khoản Nhân viên',
      users: usersRes.rows,
      currentUser: req.session.user,
      error: null,
      success: null
    });
  } catch (err) {
    console.error('[Users] List Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 2. Tạo nhân viên mới
router.post('/', async (req, res) => {
  const { username, email, full_name, role, password } = req.body;

  if (!username || !email || !full_name || !role || !password) {
    return res.status(400).send('Vui lòng điền đầy đủ tất cả các trường.');
  }

  if (!['sales', 'support', 'manager'].includes(role)) {
    return res.status(400).send('Vai trò không hợp lệ.');
  }

  try {
    const existing = await db.query('SELECT id FROM users WHERE username = $1 OR email = $2', [username.trim(), email.trim()]);
    if (existing.rows.length > 0) {
      return res.status(400).send('Tên đăng nhập hoặc email đã tồn tại trong hệ thống.');
    }

    const hash = await bcrypt.hash(password, 10);
    await db.query(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES ($1, $2, $3, $4, $5, true)
    `, [username.trim(), email.trim(), hash, full_name.trim(), role]);

    res.redirect('/users');
  } catch (err) {
    console.error('[Users] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 3. Khóa / Mở khóa tài khoản (KHÔNG cho khóa chính mình)
router.post('/:id/toggle-lock', async (req, res) => {
  const targetId = parseInt(req.params.id, 10);
  const currentUserId = req.session.user.id;

  if (targetId === currentUserId) {
    return res.status(400).send('Bảo mật hệ thống: Bạn không thể tự khóa tài khoản của chính mình!');
  }

  try {
    const uRes = await db.query('SELECT id, is_active FROM users WHERE id = $1', [targetId]);
    if (uRes.rows.length === 0) return res.status(404).send('Không tìm thấy người dùng.');

    const newActiveState = !uRes.rows[0].is_active;
    await db.query('UPDATE users SET is_active = $1 WHERE id = $2', [newActiveState, targetId]);

    res.redirect('/users');
  } catch (err) {
    console.error('[Users] Lock Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 4. Đặt lại mật khẩu nhân viên
router.post('/:id/reset-password', async (req, res) => {
  const targetId = parseInt(req.params.id, 10);
  const { new_password } = req.body;

  if (!new_password || new_password.length < 6) {
    return res.status(400).send('Mật khẩu mới phải có tối thiểu 6 ký tự.');
  }

  try {
    const hash = await bcrypt.hash(new_password, 10);
    await db.query('UPDATE users SET password_hash = $1 WHERE id = $2', [hash, targetId]);

    res.redirect('/users');
  } catch (err) {
    console.error('[Users] Reset Password Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

module.exports = router;
