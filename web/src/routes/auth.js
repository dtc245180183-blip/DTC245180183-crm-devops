const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const db = require('../db');
const { getClientIp } = require('../middlewares/auth');

router.get('/login', (req, res) => {
  if (req.session && req.session.user) {
    return res.redirect('/dashboard');
  }
  res.render('auth/login', {
    title: 'Đăng nhập hệ thống CRM',
    error: null,
    username: ''
  });
});

router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  const ip = getClientIp(req);
  const cleanUsername = (username || '').trim();

  if (!cleanUsername || !password) {
    return res.status(400).render('auth/login', {
      title: 'Đăng nhập hệ thống CRM',
      error: 'Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu.',
      username: cleanUsername
    });
  }

  try {
    const result = await db.query('SELECT * FROM users WHERE username = $1', [cleanUsername]);
    const user = result.rows[0];

    if (!user) {
      console.log(`LOGIN_FAILED ip=${ip} user=${cleanUsername} reason=unknown_user`);
      return res.status(401).render('auth/login', {
        title: 'Đăng nhập hệ thống CRM',
        error: 'Tên đăng nhập hoặc mật khẩu không chính xác.',
        username: cleanUsername
      });
    }

    if (!user.is_active) {
      console.log(`LOGIN_FAILED ip=${ip} user=${cleanUsername} reason=inactive`);
      return res.status(401).render('auth/login', {
        title: 'Đăng nhập hệ thống CRM',
        error: 'Tài khoản của bạn đã bị khóa. Vui lòng liên hệ Quản lý (Manager).',
        username: cleanUsername
      });
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      console.log(`LOGIN_FAILED ip=${ip} user=${cleanUsername} reason=wrong_password`);
      return res.status(401).render('auth/login', {
        title: 'Đăng nhập hệ thống CRM',
        error: 'Tên đăng nhập hoặc mật khẩu không chính xác.',
        username: cleanUsername
      });
    }

    // Đăng nhập thành công
    console.log(`LOGIN_SUCCESS ip=${ip} user=${cleanUsername}`);
    req.session.user = {
      id: user.id,
      username: user.username,
      email: user.email,
      full_name: user.full_name,
      role: user.role
    };

    res.redirect('/dashboard');
  } catch (err) {
    console.error('[Auth] Error handling login:', err.message);
    res.status(500).render('auth/login', {
      title: 'Đăng nhập hệ thống CRM',
      error: 'Lỗi hệ thống máy chủ CSDL. Vui lòng thử lại sau.',
      username: cleanUsername
    });
  }
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/auth/login');
  });
});

router.get('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/auth/login');
  });
});

module.exports = router;
