const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireAuth, requireRole } = require('../middlewares/auth');

function sanitizeCsv(val) {
  if (val === null || val === undefined) return '';
  let str = String(val).trim();
  // CSV Injection prevention: prefix with single quote if starts with =, +, -, @
  if (/^[=+\-@]/.test(str)) {
    str = "'" + str;
  }
  // Escape double quotes
  return `"${str.replace(/"/g, '""')}"`;
}

// 1. Export CSV (Chỉ Manager)
router.get('/export/csv', requireAuth, requireRole('manager'), async (req, res) => {
  try {
    const result = await db.query(`
      SELECT c.*, u.full_name as owner_name
      FROM customers c
      LEFT JOIN users u ON c.owner_id = u.id
      ORDER BY c.id ASC
    `);

    const headers = ['Mã KH', 'Họ và tên', 'Công ty', 'Email', 'Số điện thoại', 'Địa chỉ', 'Nguồn', 'Phân khúc', 'Người phụ trách', 'Đã lưu trữ', 'Ngày tạo'];
    let csv = '\uFEFF' + headers.map(sanitizeCsv).join(',') + '\n';

    for (const r of result.rows) {
      const row = [
        r.customer_code,
        r.full_name,
        r.company || '',
        r.email || '',
        r.phone || '',
        r.address || '',
        r.source,
        r.segment,
        r.owner_name || 'Chưa phân công',
        r.is_archived ? 'Có' : 'Không',
        r.created_at ? new Date(r.created_at).toISOString() : ''
      ];
      csv += row.map(sanitizeCsv).join(',') + '\n';
    }

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="customers_export.csv"');
    return res.status(200).send(csv);
  } catch (err) {
    console.error('[Customers] CSV Export Error:', err);
    res.status(500).send('Lỗi khi xuất danh sách CSV');
  }
});

// 2. Danh sách khách hàng có tìm kiếm, lọc, phân trang
router.get('/', requireAuth, async (req, res) => {
  const { search, segment, source, owner_id, is_archived, sort, page = 1 } = req.query;
  const limit = 10;
  const offset = (parseInt(page, 10) - 1) * limit;

  let whereClauses = [];
  let params = [];
  let paramIdx = 1;

  // Lọc theo trạng thái lưu trữ (mặc định là false)
  if (is_archived === 'true') {
    whereClauses.push(`c.is_archived = true`);
  } else if (is_archived === 'all') {
    // Không lọc
  } else {
    whereClauses.push(`c.is_archived = false`);
  }

  // Tìm kiếm theo tên / công ty / email / SĐT
  if (search && search.trim() !== '') {
    whereClauses.push(`(
      c.full_name ILIKE $${paramIdx} OR 
      c.company ILIKE $${paramIdx} OR 
      c.email ILIKE $${paramIdx} OR 
      c.phone ILIKE $${paramIdx} OR 
      c.customer_code ILIKE $${paramIdx}
    )`);
    params.push(`%${search.trim()}%`);
    paramIdx++;
  }

  // Lọc theo phân khúc
  if (segment && ['new', 'regular', 'vip', 'inactive'].includes(segment)) {
    whereClauses.push(`c.segment = $${paramIdx}`);
    params.push(segment);
    paramIdx++;
  }

  // Lọc theo nguồn
  if (source && ['website', 'referral', 'facebook', 'event', 'cold_call', 'other'].includes(source)) {
    whereClauses.push(`c.source = $${paramIdx}`);
    params.push(source);
    paramIdx++;
  }

  // Lọc theo người phụ trách
  if (owner_id && parseInt(owner_id, 10)) {
    whereClauses.push(`c.owner_id = $${paramIdx}`);
    params.push(parseInt(owner_id, 10));
    paramIdx++;
  }

  const whereStr = whereClauses.length > 0 ? 'WHERE ' + whereClauses.join(' AND ') : '';

  // Sắp xếp
  let orderBy = 'c.created_at DESC';
  if (sort === 'name_asc') orderBy = 'c.full_name ASC';
  else if (sort === 'name_desc') orderBy = 'c.full_name DESC';
  else if (sort === 'code_asc') orderBy = 'c.customer_code ASC';

  try {
    const countQuery = `SELECT COUNT(*)::int as total FROM customers c ${whereStr}`;
    const countRes = await db.query(countQuery, params);
    const totalItems = countRes.rows[0].total;
    const totalPages = Math.ceil(totalItems / limit) || 1;

    const listQuery = `
      SELECT c.*, u.full_name as owner_name
      FROM customers c
      LEFT JOIN users u ON c.owner_id = u.id
      ${whereStr}
      ORDER BY ${orderBy}
      LIMIT $${paramIdx} OFFSET $${paramIdx + 1}
    `;
    const listRes = await db.query(listQuery, [...params, limit, offset]);

    // Lấy danh sách nhân viên sales/manager để hiển thị bộ lọc
    const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('sales', 'manager') AND is_active = true ORDER BY full_name");

    res.render('customers/index', {
      title: 'Danh sách Khách hàng',
      customers: listRes.rows,
      users: usersRes.rows,
      currentPage: parseInt(page, 10),
      totalPages,
      totalItems,
      query: req.query
    });
  } catch (err) {
    console.error('[Customers] List Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 3. Form tạo khách hàng mới
router.get('/new', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  try {
    const usersRes = await db.query("SELECT id, full_name, role FROM users WHERE role IN ('sales', 'manager') AND is_active = true ORDER BY full_name");
    res.render('customers/form', {
      title: 'Thêm Khách hàng Mới',
      isEdit: false,
      customer: {},
      users: usersRes.rows,
      error: null,
      warning: null
    });
  } catch (err) {
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 4. Xử lý tạo khách hàng mới
router.post('/', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  const { full_name, company, email, phone, address, source, segment, owner_id, notes } = req.body;
  const cleanEmail = email ? email.trim() : null;
  const cleanPhone = phone ? phone.trim() : null;

  try {
    // Chặn trùng email
    if (cleanEmail) {
      const emailCheck = await db.query('SELECT id FROM customers WHERE LOWER(email) = LOWER($1)', [cleanEmail]);
      if (emailCheck.rows.length > 0) {
        const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('sales', 'manager') AND is_active = true");
        return res.status(400).render('customers/form', {
          title: 'Thêm Khách hàng Mới',
          isEdit: false,
          customer: req.body,
          users: usersRes.rows,
          error: `Email '${cleanEmail}' đã tồn tại trong hệ thống. Vui lòng nhập email khác.`,
          warning: null
        });
      }
    }

    const insertQuery = `
      INSERT INTO customers (full_name, company, email, phone, address, source, segment, owner_id, notes)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING id
    `;
    const result = await db.query(insertQuery, [
      full_name.trim(),
      company ? company.trim() : null,
      cleanEmail,
      cleanPhone,
      address ? address.trim() : null,
      source,
      segment,
      owner_id ? parseInt(owner_id, 10) : null,
      notes ? notes.trim() : null
    ]);

    res.redirect(`/customers/${result.rows[0].id}`);
  } catch (err) {
    console.error('[Customers] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 5. Chi tiết khách hàng (5 Tabs: Thông tin, Tương tác, Cơ hội, Ticket, Nhắc việc)
router.get('/:id', requireAuth, async (req, res) => {
  const customerId = parseInt(req.params.id, 10);
  if (!customerId) return res.status(404).render('error', { title: '404', status: 404, message: 'Khách hàng không tồn tại' });

  try {
    const custRes = await db.query(`
      SELECT c.*, u.full_name as owner_name, u.email as owner_email
      FROM customers c
      LEFT JOIN users u ON c.owner_id = u.id
      WHERE c.id = $1
    `, [customerId]);

    if (custRes.rows.length === 0) {
      return res.status(404).render('error', { title: '404', status: 404, message: 'Khách hàng không tồn tại' });
    }

    const customer = custRes.rows[0];

    // Lấy tương tác
    const interactionsRes = await db.query(`
      SELECT i.*, u.full_name as user_name, u.role as user_role
      FROM interactions i
      JOIN users u ON i.user_id = u.id
      WHERE i.customer_id = $1
      ORDER BY i.occurred_at DESC
    `, [customerId]);

    // Lấy cơ hội
    const opportunitiesRes = await db.query(`
      SELECT o.*, u.full_name as owner_name
      FROM opportunities o
      JOIN users u ON o.owner_id = u.id
      WHERE o.customer_id = $1
      ORDER BY o.created_at DESC
    `, [customerId]);

    // Lấy ticket (kèm kiểm tra SLA)
    const ticketsRes = await db.query(`
      SELECT t.*, u.full_name as assignee_name,
        (NOW() > t.created_at + CASE t.priority 
          WHEN 'urgent' THEN INTERVAL '4 hours'
          WHEN 'high' THEN INTERVAL '8 hours'
          WHEN 'medium' THEN INTERVAL '24 hours'
          WHEN 'low' THEN INTERVAL '72 hours'
        END AND t.status NOT IN ('resolved', 'closed')) as is_sla_overdue
      FROM tickets t
      LEFT JOIN users u ON t.assigned_to = u.id
      WHERE t.customer_id = $1
      ORDER BY t.created_at DESC
    `, [customerId]);

    // Lấy nhắc việc
    const tasksRes = await db.query(`
      SELECT t.*, u.full_name as assignee_name
      FROM tasks t
      JOIN users u ON t.assigned_to = u.id
      WHERE t.customer_id = $1
      ORDER BY t.due_at ASC
    `, [customerId]);

    res.render('customers/detail', {
      title: `Khách hàng: ${customer.full_name} (${customer.customer_code})`,
      customer,
      interactions: interactionsRes.rows,
      opportunities: opportunitiesRes.rows,
      tickets: ticketsRes.rows,
      tasks: tasksRes.rows,
      tab: req.query.tab || 'info'
    });
  } catch (err) {
    console.error('[Customers] Detail Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 6. Form chỉnh sửa khách hàng
router.get('/:id/edit', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  const customerId = parseInt(req.params.id, 10);
  try {
    const custRes = await db.query('SELECT * FROM customers WHERE id = $1', [customerId]);
    if (custRes.rows.length === 0) {
      return res.status(404).render('error', { title: '404', status: 404, message: 'Khách hàng không tồn tại' });
    }
    const usersRes = await db.query("SELECT id, full_name, role FROM users WHERE role IN ('sales', 'manager') AND is_active = true ORDER BY full_name");
    res.render('customers/form', {
      title: 'Chỉnh sửa Khách hàng',
      isEdit: true,
      customer: custRes.rows[0],
      users: usersRes.rows,
      error: null,
      warning: null
    });
  } catch (err) {
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 7. Xử lý cập nhật khách hàng
router.post('/:id/edit', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  const customerId = parseInt(req.params.id, 10);
  const { full_name, company, email, phone, address, source, segment, owner_id, notes } = req.body;
  const cleanEmail = email ? email.trim() : null;
  const cleanPhone = phone ? phone.trim() : null;

  try {
    // Chặn trùng email với khách hàng khác
    if (cleanEmail) {
      const emailCheck = await db.query('SELECT id FROM customers WHERE LOWER(email) = LOWER($1) AND id != $2', [cleanEmail, customerId]);
      if (emailCheck.rows.length > 0) {
        const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('sales', 'manager') AND is_active = true");
        return res.status(400).render('customers/form', {
          title: 'Chỉnh sửa Khách hàng',
          isEdit: true,
          customer: { ...req.body, id: customerId },
          users: usersRes.rows,
          error: `Email '${cleanEmail}' đã thuộc về một khách hàng khác. Vui lòng nhập email khác.`,
          warning: null
        });
      }
    }

    const updateQuery = `
      UPDATE customers 
      SET full_name = $1, company = $2, email = $3, phone = $4, address = $5, source = $6, segment = $7, owner_id = $8, notes = $9, updated_at = NOW()
      WHERE id = $10
    `;
    await db.query(updateQuery, [
      full_name.trim(),
      company ? company.trim() : null,
      cleanEmail,
      cleanPhone,
      address ? address.trim() : null,
      source,
      segment,
      owner_id ? parseInt(owner_id, 10) : null,
      notes ? notes.trim() : null,
      customerId
    ]);

    res.redirect(`/customers/${customerId}`);
  } catch (err) {
    console.error('[Customers] Update Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 8. Lưu trữ / Khôi phục khách hàng (Chỉ Manager)
router.post('/:id/archive', requireAuth, requireRole('manager'), async (req, res) => {
  const customerId = parseInt(req.params.id, 10);
  try {
    await db.query('UPDATE customers SET is_archived = true, updated_at = NOW() WHERE id = $1', [customerId]);
    res.redirect(`/customers/${customerId}`);
  } catch (err) {
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

router.post('/:id/restore', requireAuth, requireRole('manager'), async (req, res) => {
  const customerId = parseInt(req.params.id, 10);
  try {
    await db.query('UPDATE customers SET is_archived = false, updated_at = NOW() WHERE id = $1', [customerId]);
    res.redirect(`/customers/${customerId}`);
  } catch (err) {
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

module.exports = router;
