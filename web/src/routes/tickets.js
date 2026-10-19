const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { requireAuth, requireRole } = require('../middlewares/auth');
const { upload, verifyMagicBytes, UPLOADS_DIR } = require('../middlewares/upload');

const SLA_HOURS = {
  urgent: 4,
  high: 8,
  medium: 24,
  low: 72
};

// 1. Danh sách Ticket
router.get('/', requireAuth, async (req, res) => {
  const { status, priority, category, assigned_to } = req.query;

  let whereClauses = [];
  let params = [];
  let idx = 1;

  if (status && ['open', 'in_progress', 'resolved', 'closed'].includes(status)) {
    whereClauses.push(`t.status = $${idx++}`);
    params.push(status);
  }
  if (priority && ['low', 'medium', 'high', 'urgent'].includes(priority)) {
    whereClauses.push(`t.priority = $${idx++}`);
    params.push(priority);
  }
  if (category && ['technical', 'billing', 'complaint', 'consulting', 'other'].includes(category)) {
    whereClauses.push(`t.category = $${idx++}`);
    params.push(category);
  }
  if (assigned_to && parseInt(assigned_to, 10)) {
    whereClauses.push(`t.assigned_to = $${idx++}`);
    params.push(parseInt(assigned_to, 10));
  }

  const whereStr = whereClauses.length > 0 ? 'WHERE ' + whereClauses.join(' AND ') : '';

  try {
    const listRes = await db.query(`
      SELECT t.*, c.full_name as customer_name, c.customer_code, 
             u1.full_name as creator_name, u2.full_name as assignee_name,
             (NOW() > t.created_at + CASE t.priority 
               WHEN 'urgent' THEN INTERVAL '4 hours'
               WHEN 'high' THEN INTERVAL '8 hours'
               WHEN 'medium' THEN INTERVAL '24 hours'
               WHEN 'low' THEN INTERVAL '72 hours'
             END AND t.status NOT IN ('resolved', 'closed')) as is_sla_overdue
      FROM tickets t
      JOIN customers c ON t.customer_id = c.id
      JOIN users u1 ON t.created_by = u1.id
      LEFT JOIN users u2 ON t.assigned_to = u2.id
      ${whereStr}
      ORDER BY t.created_at DESC
    `, params);

    const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('support', 'manager') AND is_active = true");
    const customersRes = await db.query("SELECT id, customer_code, full_name FROM customers WHERE is_archived = false ORDER BY full_name");

    res.render('tickets/index', {
      title: 'Quản lý Phiếu Hỗ trợ & Khiếu nại (Tickets)',
      tickets: listRes.rows,
      users: usersRes.rows,
      customers: customersRes.rows,
      query: req.query,
      slaHours: SLA_HOURS
    });
  } catch (err) {
    console.error('[Tickets] List Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 2. Tạo ticket mới (sales/support/manager)
router.post('/', requireAuth, async (req, res) => {
  const { customer_id, subject, description, category, priority, assigned_to } = req.body;
  const user = req.session.user;

  if (!customer_id || !subject || !description || !category || !priority) {
    return res.status(400).send('Vui lòng điền đầy đủ các thông tin bắt buộc.');
  }

  try {
    const assignId = (user.role === 'manager' && assigned_to) ? parseInt(assigned_to, 10) : null;

    const result = await db.query(`
      INSERT INTO tickets (customer_id, created_by, assigned_to, subject, description, category, priority, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'open')
      RETURNING id
    `, [parseInt(customer_id, 10), user.id, assignId, subject.trim(), description.trim(), category, priority]);

    res.redirect(`/tickets/${result.rows[0].id}`);
  } catch (err) {
    console.error('[Tickets] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 3. Chi tiết ticket và bình luận
router.get('/:id', requireAuth, async (req, res) => {
  const ticketId = parseInt(req.params.id, 10);
  try {
    const tRes = await db.query(`
      SELECT t.*, c.full_name as customer_name, c.customer_code, c.email as customer_email, c.phone as customer_phone,
             u1.full_name as creator_name, u2.full_name as assignee_name,
             (NOW() > t.created_at + CASE t.priority 
               WHEN 'urgent' THEN INTERVAL '4 hours'
               WHEN 'high' THEN INTERVAL '8 hours'
               WHEN 'medium' THEN INTERVAL '24 hours'
               WHEN 'low' THEN INTERVAL '72 hours'
             END AND t.status NOT IN ('resolved', 'closed')) as is_sla_overdue
      FROM tickets t
      JOIN customers c ON t.customer_id = c.id
      JOIN users u1 ON t.created_by = u1.id
      LEFT JOIN users u2 ON t.assigned_to = u2.id
      WHERE t.id = $1
    `, [ticketId]);

    if (tRes.rows.length === 0) return res.status(404).render('error', { title: '404', status: 404, message: 'Ticket không tồn tại.' });

    const ticket = tRes.rows[0];

    // Lấy danh sách bình luận
    const commentsRes = await db.query(`
      SELECT tc.*, u.full_name as user_name, u.role as user_role
      FROM ticket_comments tc
      JOIN users u ON tc.user_id = u.id
      WHERE tc.ticket_id = $1
      ORDER BY tc.created_at ASC
    `, [ticketId]);

    const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('support', 'manager') AND is_active = true");

    res.render('tickets/detail', {
      title: `Ticket: ${ticket.ticket_code} - ${ticket.subject}`,
      ticket,
      comments: commentsRes.rows,
      users: usersRes.rows,
      canManage: ['support', 'manager'].includes(req.session.user.role),
      slaHours: SLA_HOURS
    });
  } catch (err) {
    console.error('[Tickets] Detail Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 4. Đổi trạng thái ticket (support/manager)
router.post('/:id/status', requireAuth, requireRole('support', 'manager'), async (req, res) => {
  const ticketId = parseInt(req.params.id, 10);
  const { target_status } = req.body;

  try {
    const tRes = await db.query('SELECT * FROM tickets WHERE id = $1', [ticketId]);
    if (tRes.rows.length === 0) return res.status(404).send('Không tìm thấy ticket.');

    const ticket = tRes.rows[0];
    const current = ticket.status;

    if (current === 'closed') {
      return res.status(400).send('Ticket đã Đóng (Closed), không thể thay đổi trạng thái.');
    }

    let isValid = false;
    let setResolvedAt = null;

    if (current === 'open' && target_status === 'in_progress') isValid = true;
    else if (current === 'in_progress' && target_status === 'resolved') {
      isValid = true;
      setResolvedAt = 'NOW()';
    }
    else if (current === 'resolved' && target_status === 'closed') isValid = true;
    else if (current === 'resolved' && target_status === 'in_progress') {
      isValid = true;
      setResolvedAt = 'NULL';
    }

    if (!isValid) {
      return res.status(400).send(`Chuyển trạng thái không hợp lệ từ '${current}' sang '${target_status}'. Luồng hợp lệ: open → in_progress → resolved → closed (hoặc resolved → in_progress để mở lại).`);
    }

    if (setResolvedAt) {
      await db.query(`UPDATE tickets SET status = $1, resolved_at = ${setResolvedAt}, updated_at = NOW() WHERE id = $2`, [target_status, ticketId]);
    } else {
      await db.query(`UPDATE tickets SET status = $1, updated_at = NOW() WHERE id = $2`, [target_status, ticketId]);
    }

    res.redirect(`/tickets/${ticketId}`);
  } catch (err) {
    console.error('[Tickets] Status Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 5. Phân công ticket (manager phân công hoặc support nhận xử lý)
router.post('/:id/assign', requireAuth, requireRole('support', 'manager'), async (req, res) => {
  const ticketId = parseInt(req.params.id, 10);
  const user = req.session.user;
  const targetUserId = (user.role === 'manager' && req.body.assigned_to) ? parseInt(req.body.assigned_to, 10) : user.id;

  try {
    await db.query('UPDATE tickets SET assigned_to = $1, updated_at = NOW() WHERE id = $2', [targetUserId, ticketId]);
    res.redirect(`/tickets/${ticketId}`);
  } catch (err) {
    console.error('[Tickets] Assign Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 6. Thêm bình luận và đính kèm tệp (kiểm tra magic bytes, kích thước, định dạng)
router.post('/:id/comments', requireAuth, (req, res, next) => {
  upload.single('attachment')(req, res, (err) => {
    if (err) {
      return res.status(400).send(`Lỗi tải lên tệp: ${err.message}`);
    }

    // Xác thực CSRF token cho multipart sau khi multer parse body
    const token = req.body?._csrf || req.headers['x-csrf-token'] || req.headers['csrf-token'] || req.query?._csrf;
    if (!token || token !== req.session.csrfToken) {
      if (req.file) {
        try { fs.unlinkSync(req.file.path); } catch(e) {}
      }
      return res.status(403).send('Mã xác thực CSRF không hợp lệ hoặc phiên làm việc đã hết hạn.');
    }

    next();
  });
}, async (req, res) => {
  const ticketId = parseInt(req.params.id, 10);
  const { content } = req.body;
  const user = req.session.user;

  if (!content || content.trim() === '') {
    if (req.file) {
      try { fs.unlinkSync(req.file.path); } catch(e) {}
    }
    return res.status(400).send('Nội dung bình luận không được để trống.');
  }

  let attachmentPath = null;
  let attachmentName = null;

  if (req.file) {
    // Kiểm tra Magic Bytes
    const isMagicValid = verifyMagicBytes(req.file.path);
    if (!isMagicValid) {
      try { fs.unlinkSync(req.file.path); } catch(e) {}
      return res.status(400).send('Tệp đính kèm không hợp lệ (Phần mở rộng không khớp với cấu trúc byte thực tế của tệp PNG/JPG/WEBP/PDF).');
    }
    attachmentPath = req.file.filename;
    attachmentName = req.file.originalname;
  }

  try {
    await db.query(`
      INSERT INTO ticket_comments (ticket_id, user_id, content, attachment_path, attachment_name)
      VALUES ($1, $2, $3, $4, $5)
    `, [ticketId, user.id, content.trim(), attachmentPath, attachmentName]);

    res.redirect(`/tickets/${ticketId}`);
  } catch (err) {
    if (req.file) {
      try { fs.unlinkSync(req.file.path); } catch(e) {}
    }
    console.error('[Tickets] Comment Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 7. Tải xuống tệp đính kèm (có kiểm tra đăng nhập, KHÔNG phục vụ công khai tĩnh)
router.get('/attachments/:filename', requireAuth, (req, res) => {
  const filename = path.basename(req.params.filename);
  const filePath = path.join(UPLOADS_DIR, filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).send('Tệp đính kèm không tồn tại.');
  }

  res.sendFile(filePath);
});

module.exports = router;
