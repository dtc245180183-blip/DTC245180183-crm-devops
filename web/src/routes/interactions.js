const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireAuth } = require('../middlewares/auth');

// Thêm tương tác
router.post('/', requireAuth, async (req, res) => {
  const { customer_id, type, subject, content, occurred_at } = req.body;
  const user = req.session.user;

  if (!customer_id || !subject || !content || !type) {
    return res.status(400).send('Vui lòng điền đầy đủ thông tin tương tác.');
  }

  try {
    const occTime = occurred_at ? new Date(occurred_at) : new Date();
    await db.query(`
      INSERT INTO interactions (customer_id, user_id, type, subject, content, occurred_at)
      VALUES ($1, $2, $3, $4, $5, $6)
    `, [parseInt(customer_id, 10), user.id, type, subject.trim(), content.trim(), occTime]);

    res.redirect(`/customers/${customer_id}?tab=interactions`);
  } catch (err) {
    console.error('[Interactions] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// Sửa tương tác (chỉ người tạo hoặc manager)
router.post('/:id/edit', requireAuth, async (req, res) => {
  const interactionId = parseInt(req.params.id, 10);
  const { type, subject, content, occurred_at } = req.body;
  const user = req.session.user;

  try {
    const intRes = await db.query('SELECT * FROM interactions WHERE id = $1', [interactionId]);
    if (intRes.rows.length === 0) return res.status(404).send('Không tìm thấy tương tác.');

    const interaction = intRes.rows[0];
    if (user.role !== 'manager' && interaction.user_id !== user.id) {
      return res.status(403).render('error', { title: '403', status: 403, message: 'Bạn chỉ có quyền sửa tương tác do chính mình tạo.' });
    }

    const occTime = occurred_at ? new Date(occurred_at) : interaction.occurred_at;
    await db.query(`
      UPDATE interactions 
      SET type = $1, subject = $2, content = $3, occurred_at = $4
      WHERE id = $5
    `, [type, subject.trim(), content.trim(), occTime, interactionId]);

    res.redirect(`/customers/${interaction.customer_id}?tab=interactions`);
  } catch (err) {
    console.error('[Interactions] Edit Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// Xóa tương tác (chỉ người tạo hoặc manager)
router.post('/:id/delete', requireAuth, async (req, res) => {
  const interactionId = parseInt(req.params.id, 10);
  const user = req.session.user;

  try {
    const intRes = await db.query('SELECT * FROM interactions WHERE id = $1', [interactionId]);
    if (intRes.rows.length === 0) return res.status(404).send('Không tìm thấy tương tác.');

    const interaction = intRes.rows[0];
    if (user.role !== 'manager' && interaction.user_id !== user.id) {
      return res.status(403).render('error', { title: '403', status: 403, message: 'Bạn chỉ có quyền xóa tương tác do chính mình tạo.' });
    }

    await db.query('DELETE FROM interactions WHERE id = $1', [interactionId]);
    res.redirect(`/customers/${interaction.customer_id}?tab=interactions`);
  } catch (err) {
    console.error('[Interactions] Delete Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

module.exports = router;
