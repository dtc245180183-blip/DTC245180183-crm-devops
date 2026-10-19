const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireAuth, requireRole } = require('../middlewares/auth');

const STAGE_CONFIG = {
  new:       { index: 0, next: 'contacted', prob: 10,  label: 'Mới tạo' },
  contacted: { index: 1, next: 'qualified', prob: 25,  label: 'Đã liên hệ' },
  qualified: { index: 2, next: 'proposal',  prob: 50,  label: 'Đủ điều kiện' },
  proposal:  { index: 3, next: 'won',       prob: 75,  label: 'Gửi đề xuất' },
  won:       { index: 4, next: null,        prob: 100, label: 'Thành công (Won)' },
  lost:      { index: 5, next: null,        prob: 0,   label: 'Thất bại (Lost)' }
};

// 1. Kanban Pipeline View (sales/support/manager đều xem được)
router.get('/', requireAuth, async (req, res) => {
  try {
    const oppsRes = await db.query(`
      SELECT o.*, c.full_name as customer_name, c.customer_code, u.full_name as owner_name
      FROM opportunities o
      JOIN customers c ON o.customer_id = c.id
      JOIN users u ON o.owner_id = u.id
      ORDER BY o.created_at DESC
    `);

    // Nhóm theo giai đoạn
    const stages = {
      new: [],
      contacted: [],
      qualified: [],
      proposal: [],
      won: [],
      lost: []
    };

    let totalPipelineValue = 0;
    for (const opp of oppsRes.rows) {
      if (stages[opp.stage]) {
        stages[opp.stage].push(opp);
      }
      if (opp.stage !== 'lost') {
        totalPipelineValue += Number(opp.value);
      }
    }

    const customersRes = await db.query("SELECT id, customer_code, full_name FROM customers WHERE is_archived = false ORDER BY full_name");
    const usersRes = await db.query("SELECT id, full_name FROM users WHERE role IN ('sales', 'manager') AND is_active = true ORDER BY full_name");

    res.render('opportunities/kanban', {
      title: 'Sales Pipeline (Kanban)',
      stages,
      stageConfig: STAGE_CONFIG,
      totalPipelineValue,
      customers: customersRes.rows,
      users: usersRes.rows,
      canEdit: ['sales', 'manager'].includes(req.session.user.role)
    });
  } catch (err) {
    console.error('[Opportunities] List Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 2. Thêm cơ hội mới (sales/manager)
router.post('/', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  const { customer_id, title, value, stage = 'new', expected_close, owner_id } = req.body;
  const user = req.session.user;

  if (!customer_id || !title || value === undefined || value === '') {
    return res.status(400).send('Vui lòng điền các trường bắt buộc (Khách hàng, Tiêu đề, Giá trị).');
  }

  const numValue = Number(value);
  if (isNaN(numValue) || numValue < 0) {
    return res.status(400).send('Giá trị cơ hội phải là số không âm.');
  }

  const validStage = STAGE_CONFIG[stage] ? stage : 'new';
  const prob = STAGE_CONFIG[validStage].prob;
  const owner = owner_id ? parseInt(owner_id, 10) : user.id;

  try {
    await db.query(`
      INSERT INTO opportunities (customer_id, title, value, stage, probability, expected_close, owner_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, [parseInt(customer_id, 10), title.trim(), numValue, validStage, prob, expected_close || null, owner]);

    res.redirect('/opportunities');
  } catch (err) {
    console.error('[Opportunities] Create Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

// 3. Chuyển giai đoạn cơ hội theo quy tắc nghiêm ngặt (sales/manager)
router.post('/:id/stage', requireAuth, requireRole('sales', 'manager'), async (req, res) => {
  const oppId = parseInt(req.params.id, 10);
  const { target_stage, lost_reason } = req.body;

  try {
    const oppRes = await db.query('SELECT * FROM opportunities WHERE id = $1', [oppId]);
    if (oppRes.rows.length === 0) return res.status(404).send('Không tìm thấy cơ hội bán hàng.');

    const opp = oppRes.rows[0];
    const currentStage = opp.stage;

    // Quy tắc: won và lost là giai đoạn kết thúc, không được đổi nữa
    if (currentStage === 'won' || currentStage === 'lost') {
      return res.status(400).send(`Cơ hội đã ở trạng thái kết thúc (${currentStage.toUpperCase()}), không thể thay đổi giai đoạn.`);
    }

    if (!STAGE_CONFIG[target_stage]) {
      return res.status(400).send('Giai đoạn chuyển đến không hợp lệ.');
    }

    // Quy tắc chuyển:
    // 1. Chuyển sang lost: cho phép từ bất kỳ giai đoạn chưa kết thúc nào, nhưng BẮT BUỘC có lý do
    if (target_stage === 'lost') {
      if (!lost_reason || lost_reason.trim() === '') {
        return res.status(400).send('Chuyển sang trạng thái Lost bắt buộc phải nhập lý do thất bại.');
      }
      await db.query(`
        UPDATE opportunities 
        SET stage = 'lost', probability = 0, lost_reason = $1, closed_at = NOW()
        WHERE id = $2
      `, [lost_reason.trim(), oppId]);
      return res.redirect('/opportunities');
    }

    // 2. Chuyển tiến: chỉ được tiến lên giai đoạn kế tiếp theo chuỗi tuần tự
    const expectedNext = STAGE_CONFIG[currentStage].next;
    if (target_stage !== expectedNext) {
      return res.status(400).send(`Chuyển giai đoạn không hợp lệ! Từ '${currentStage}' chỉ có thể tiến lên '${expectedNext}' hoặc chuyển sang 'lost'.`);
    }

    const newProb = STAGE_CONFIG[target_stage].prob;
    const closedAt = target_stage === 'won' ? 'NOW()' : 'NULL';

    await db.query(`
      UPDATE opportunities 
      SET stage = $1, probability = $2, closed_at = ${closedAt}
      WHERE id = $3
    `, [target_stage, newProb, oppId]);

    res.redirect('/opportunities');
  } catch (err) {
    console.error('[Opportunities] Stage Transition Error:', err);
    res.status(500).render('error', { title: 'Lỗi', status: 500, message: err.message });
  }
});

module.exports = router;
