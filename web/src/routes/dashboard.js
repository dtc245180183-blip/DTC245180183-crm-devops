const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireAuth } = require('../middlewares/auth');

router.get('/', requireAuth, async (req, res) => {
  const user = req.session.user;

  try {
    if (user.role === 'manager') {
      // 1. Phân khúc khách hàng
      const segmentRes = await db.query(
        "SELECT segment, COUNT(*)::int as count FROM customers WHERE is_archived = false GROUP BY segment"
      );

      // 2. Khách hàng mới trong tháng
      const newCustRes = await db.query(
        "SELECT COUNT(*)::int as count FROM customers WHERE created_at >= date_trunc('month', NOW()) AND is_archived = false"
      );

      // 3. Pipeline theo giai đoạn
      const pipelineRes = await db.query(
        "SELECT stage, COUNT(*)::int as count, COALESCE(SUM(value), 0)::numeric as total_value FROM opportunities GROUP BY stage"
      );

      // 4. Tỉ lệ thắng & Doanh thu Won
      const winRateRes = await db.query(`
        SELECT 
          COUNT(*) FILTER (WHERE stage = 'won')::int as won_count,
          COUNT(*) FILTER (WHERE stage = 'lost')::int as lost_count,
          COALESCE(SUM(value) FILTER (WHERE stage = 'won'), 0)::numeric as total_won_value,
          COALESCE(SUM(value) FILTER (WHERE stage = 'won' AND closed_at >= date_trunc('month', NOW())), 0)::numeric as month_won_value
        FROM opportunities
      `);

      // 5. Thống kê ticket & SLA Quá hạn
      const ticketRes = await db.query(`
        SELECT 
          status, priority, COUNT(*)::int as count
        FROM tickets 
        GROUP BY status, priority
      `);

      const slaRes = await db.query(`
        SELECT COUNT(*)::int as overdue_count
        FROM tickets
        WHERE status NOT IN ('resolved', 'closed')
          AND NOW() > created_at + CASE priority 
            WHEN 'urgent' THEN INTERVAL '4 hours'
            WHEN 'high' THEN INTERVAL '8 hours'
            WHEN 'medium' THEN INTERVAL '24 hours'
            WHEN 'low' THEN INTERVAL '72 hours'
          END
      `);

      // 6. Thời gian xử lý ticket trung bình (giờ)
      const avgRes = await db.query(`
        SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (resolved_at - created_at)) / 3600)::numeric, 1), 0)::float as avg_hours
        FROM tickets
        WHERE resolved_at IS NOT NULL
      `);

      // 7. Top nhân viên theo doanh thu thắng
      const topStaffRes = await db.query(`
        SELECT u.full_name, u.role, COALESCE(SUM(o.value), 0)::numeric as total_won, COUNT(o.id)::int as won_deals
        FROM users u
        LEFT JOIN opportunities o ON u.id = o.owner_id AND o.stage = 'won'
        WHERE u.role IN ('sales', 'manager')
        GROUP BY u.id, u.full_name, u.role
        ORDER BY total_won DESC
        LIMIT 5
      `);

      return res.render('dashboard/index', {
        title: 'Bảng điều khiển KPI Quản lý',
        isManager: true,
        segments: segmentRes.rows,
        newCustomersMonth: newCustRes.rows[0].count,
        pipeline: pipelineRes.rows,
        winMetrics: winRateRes.rows[0],
        tickets: ticketRes.rows,
        slaOverdueCount: slaRes.rows[0].overdue_count,
        avgResolutionHours: avgRes.rows[0].avg_hours,
        topStaff: topStaffRes.rows,
      });
    } else {
      // Dashboard cá nhân cho sales / support
      const myTasks = await db.query(`
        SELECT t.*, c.full_name as customer_name
        FROM tasks t
        LEFT JOIN customers c ON t.customer_id = c.id
        WHERE t.assigned_to = $1 AND t.status = 'todo'
        ORDER BY t.due_at ASC
        LIMIT 6
      `, [user.id]);

      const myOpportunities = await db.query(`
        SELECT o.*, c.full_name as customer_name
        FROM opportunities o
        JOIN customers c ON o.customer_id = c.id
        WHERE o.owner_id = $1 AND o.stage NOT IN ('won', 'lost')
        ORDER BY o.created_at DESC
        LIMIT 5
      `, [user.id]);

      const myTickets = await db.query(`
        SELECT t.*, c.full_name as customer_name,
          (NOW() > t.created_at + CASE t.priority 
            WHEN 'urgent' THEN INTERVAL '4 hours'
            WHEN 'high' THEN INTERVAL '8 hours'
            WHEN 'medium' THEN INTERVAL '24 hours'
            WHEN 'low' THEN INTERVAL '72 hours'
          END AND t.status NOT IN ('resolved', 'closed')) as is_sla_overdue
        FROM tickets t
        JOIN customers c ON t.customer_id = c.id
        WHERE (t.assigned_to = $1 OR t.created_by = $1)
          AND t.status NOT IN ('closed')
        ORDER BY t.created_at DESC
        LIMIT 5
      `, [user.id]);

      return res.render('dashboard/index', {
        title: 'Bảng điều khiển công việc cá nhân',
        isManager: false,
        tasks: myTasks.rows,
        opportunities: myOpportunities.rows,
        tickets: myTickets.rows,
      });
    }
  } catch (err) {
    console.error('[Dashboard] Error rendering dashboard:', err);
    res.status(500).render('error', {
      title: 'Lỗi tải trang Dashboard',
      status: 500,
      message: 'Không thể truy xuất dữ liệu báo cáo: ' + err.message
    });
  }
});

module.exports = router;
