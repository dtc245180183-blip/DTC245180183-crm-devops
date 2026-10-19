const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireAuth } = require('../middlewares/auth');

// 1. Danh sách nhắc việc
router.get('/', requireAuth, async (req, res) => {
  const user = req.session.user;
  const { status = 'all', timeframe = 'all', assigned_to } = req.query;

  let whereClauses = [];
  let params = [];
  let idx = 1;

  // Quyền: Manager thấy tất cả, Sales/Support chỉ thấy việc của mình
  if (user.role === 'manager') {
    if (assigned_to && parseInt(assigned_to, 10)) {
      whereClauses.push(`t.assigned_to = $${idx++}`);
      params.push(parseInt(assigned_to, 10));
    }
  } else {
    whereClauses.push(`t.assigned_to = $${idx++}`);
    params.push(user.id);
  }

  // Lọc theo trạng thái
  if (status === 'todo') {
    whereClauses.push(`t.status = 'todo'`);
  } else if (status === 'done') {
    whereClauses.push(`t.status = 'done'`);
  }

  // Lọc theo thời hạn
  if (timeframe === 'today') {
    whereClauses.push(`t.due_at::date = CURRENT_DATE`);
  } else if (timeframe === 'overdue') {
    whereClauses.push(`t.due_at < NOW() AND t.status = 'todo'`);
  }

  const whereStr = whereClauses.length > 0 ? 'WHERE ' + whereClauses.join(' AND ') : '';

  try {
    const listRes = await db.query(`
      SELECT t.*, c.full_name as customer_name, c.customer_code,
             u1.full_name as creator_name, u2.full_name as assignee_name,
             (t.due_at < NOW() AND t.status = 'todo') as is_overdue,
             (t.due_at::date = CURRENT_DATE AND t.status = 'todo') as is_today
      FROM tasks t
      LEFT JOIN customers c ON t.customer_id = c.id
      JOIN users u1 ON t.created_by = u1.id
      JOIN users u2 ON t.assigned_to = u2.id
      ${whereStr}
      ORDER BY t.status ASC, t.due_at ASC
    `, params);

    const usersRes = await db.query("SELECT id, full_name, role FROM users WHERE is_active = true ORDER BY full_name");
    const customersRes = await db.query("SELECT id, customer_code, full_name FROM customers WHERE is_archived = false ORDER BY full_name");

    res.render('tasks/index', {
      title: 'Quản lý Lịch Nhắc Việc (Tasks)',
      tasks: listRes.rows,
      users: usersRes.rows,
      customers: customersRes.rows,
      query: req.query,
      isManager: user.role === 'manager'
    });
  } catch (err) {
    console.error('[Tasks] List Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 2. Tạo nhắc việc mới
router.post('/', requireAuth, async (req, res) => {
  const { title, description, customer_id, due_at, assigned_to } = req.body;
  const user = req.session.user;

  if (!title || !due_at) {
    return res.status(400).send('Vui lòng nhập tiêu đề và thời hạn nhắc việc.');
  }

  const targetAssignee = (user.role === 'manager' && assigned_to) ? parseInt(assigned_to, 10) : user.id;

  try {
    await db.query(`
      INSERT INTO tasks (title, description, customer_id, assigned_to, created_by, due_at, status)
      VALUES ($1, $2, $3, $4, $5, $6, 'todo')
    `, [
      title.trim(),
      description ? description.trim() : null,
      customer_id ? parseInt(customer_id, 10) : null,
      targetAssignee,
      user.id,
      new Date(due_at)
    ]);

    res.redirect('/tasks');
  } catch (err) {
    console.error('[Tasks] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 3. Đổi trạng thái hoàn thành / chưa hoàn thành
router.post('/:id/toggle', requireAuth, async (req, res) => {
  const taskId = parseInt(req.params.id, 10);
  const user = req.session.user;

  try {
    const tRes = await db.query('SELECT * FROM tasks WHERE id = $1', [taskId]);
    if (tRes.rows.length === 0) return res.status(404).send('Không tìm thấy nhắc việc.');

    const task = tRes.rows[0];
    if (user.role !== 'manager' && task.assigned_to !== user.id) {
      return res.status(403).send('Bạn không có quyền thay đổi trạng thái nhắc việc của người khác.');
    }

    if (task.status === 'todo') {
      await db.query("UPDATE tasks SET status = 'done', completed_at = NOW() WHERE id = $1", [taskId]);
    } else {
      await db.query("UPDATE tasks SET status = 'todo', completed_at = NULL WHERE id = $1", [taskId]);
    }

    res.redirect('/tasks');
  } catch (err) {
    console.error('[Tasks] Toggle Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 4. Xóa nhắc việc
router.post('/:id/delete', requireAuth, async (req, res) => {
  const taskId = parseInt(req.params.id, 10);
  const user = req.session.user;

  try {
    const tRes = await db.query('SELECT * FROM tasks WHERE id = $1', [taskId]);
    if (tRes.rows.length === 0) return res.status(404).send('Không tìm thấy nhắc việc.');

    const task = tRes.rows[0];
    if (user.role !== 'manager' && task.created_by !== user.id && task.assigned_to !== user.id) {
      return res.status(403).send('Bạn không có quyền xóa nhắc việc này.');
    }

    await db.query('DELETE FROM tasks WHERE id = $1', [taskId]);
    res.redirect('/tasks');
  } catch (err) {
    console.error('[Tasks] Delete Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

module.exports = router;
