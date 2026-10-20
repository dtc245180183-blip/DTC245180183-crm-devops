-- =============================================================================
-- Hệ thống CRM Chăm sóc Khách hàng - Database Initialization Script
-- CSDL: PostgreSQL 16
-- Sinh viên: Dương Tiến Dũng | MSSV: DTC245180183 | Lớp: KTPM K23B
-- =============================================================================

-- Thiết lập múi giờ Việt Nam (UTC+7)
SET timezone = 'Asia/Ho_Chi_Minh';

-- Xóa bảng cũ nếu tồn tại (theo thứ tự khóa ngoại)
DROP TABLE IF EXISTS tasks CASCADE;
DROP TABLE IF EXISTS ticket_comments CASCADE;
DROP TABLE IF EXISTS tickets CASCADE;
DROP TABLE IF EXISTS opportunities CASCADE;
DROP TABLE IF EXISTS interactions CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP SEQUENCE IF EXISTS customers_code_seq CASCADE;
DROP SEQUENCE IF EXISTS ticket_code_seq CASCADE;

-- -----------------------------------------------------------------------------
-- 1. BẢNG USERS (Tài khoản người dùng và phân quyền)
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('sales', 'support', 'manager')),
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_active ON users(is_active);

-- -----------------------------------------------------------------------------
-- 2. BẢNG CUSTOMERS (Hồ sơ khách hàng và phân khúc)
-- -----------------------------------------------------------------------------
CREATE SEQUENCE customers_code_seq START WITH 1;

CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    customer_code VARCHAR(20) UNIQUE NOT NULL DEFAULT ('KH' || LPAD(nextval('customers_code_seq')::TEXT, 4, '0')),
    full_name VARCHAR(100) NOT NULL,
    company VARCHAR(150),
    email VARCHAR(100),
    phone VARCHAR(20),
    address TEXT,
    source VARCHAR(30) NOT NULL CHECK (source IN ('website', 'referral', 'facebook', 'event', 'cold_call', 'other')),
    segment VARCHAR(20) NOT NULL CHECK (segment IN ('new', 'regular', 'vip', 'inactive')),
    owner_id INT REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    is_archived BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Unique index không phân biệt hoa thường cho email (khi email khác NULL)
CREATE UNIQUE INDEX customers_email_lower_idx ON customers (LOWER(email)) WHERE email IS NOT NULL;

CREATE INDEX idx_customers_owner ON customers(owner_id);
CREATE INDEX idx_customers_segment ON customers(segment);
CREATE INDEX idx_customers_source ON customers(source);
CREATE INDEX idx_customers_archived ON customers(is_archived);
CREATE INDEX idx_customers_created_at ON customers(created_at);

-- -----------------------------------------------------------------------------
-- 3. BẢNG INTERACTIONS (Lịch sử tương tác chăm sóc khách hàng)
-- -----------------------------------------------------------------------------
CREATE TABLE interactions (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    type VARCHAR(20) NOT NULL CHECK (type IN ('call', 'email', 'meeting', 'note', 'chat')),
    subject VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    occurred_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_interactions_customer ON interactions(customer_id);
CREATE INDEX idx_interactions_user ON interactions(user_id);
CREATE INDEX idx_interactions_occurred_at ON interactions(occurred_at);

-- -----------------------------------------------------------------------------
-- 4. BẢNG OPPORTUNITIES (Cơ hội bán hàng - Sales Pipeline)
-- -----------------------------------------------------------------------------
CREATE TABLE opportunities (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    value NUMERIC(14,0) NOT NULL CHECK (value >= 0),
    stage VARCHAR(20) NOT NULL CHECK (stage IN ('new', 'contacted', 'qualified', 'proposal', 'won', 'lost')),
    probability INT NOT NULL CHECK (probability >= 0 AND probability <= 100),
    expected_close DATE,
    owner_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    lost_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    closed_at TIMESTAMPTZ
);

CREATE INDEX idx_opportunities_customer ON opportunities(customer_id);
CREATE INDEX idx_opportunities_owner ON opportunities(owner_id);
CREATE INDEX idx_opportunities_stage ON opportunities(stage);
CREATE INDEX idx_opportunities_created_at ON opportunities(created_at);

-- -----------------------------------------------------------------------------
-- 5. BẢNG TICKETS (Phiếu yêu cầu hỗ trợ và khiếu nại)
-- -----------------------------------------------------------------------------
CREATE SEQUENCE ticket_code_seq START WITH 1;

CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    ticket_code VARCHAR(30) UNIQUE NOT NULL DEFAULT ('TK-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('ticket_code_seq')::TEXT, 4, '0')),
    customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    created_by INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    assigned_to INT REFERENCES users(id) ON DELETE SET NULL,
    subject VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(30) NOT NULL CHECK (category IN ('technical', 'billing', 'complaint', 'consulting', 'other')),
    priority VARCHAR(20) NOT NULL CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_tickets_customer ON tickets(customer_id);
CREATE INDEX idx_tickets_assigned ON tickets(assigned_to);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_priority ON tickets(priority);
CREATE INDEX idx_tickets_created_at ON tickets(created_at);

-- -----------------------------------------------------------------------------
-- 6. BẢNG TICKET_COMMENTS (Bình luận & tệp đính kèm xử lý ticket)
-- -----------------------------------------------------------------------------
CREATE TABLE ticket_comments (
    id SERIAL PRIMARY KEY,
    ticket_id INT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    content TEXT NOT NULL,
    attachment_path VARCHAR(255),
    attachment_name VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_ticket_comments_ticket ON ticket_comments(ticket_id);

-- -----------------------------------------------------------------------------
-- 7. BẢNG TASKS (Lịch nhắc việc chăm sóc và hỗ trợ)
-- -----------------------------------------------------------------------------
CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
    assigned_to INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_by INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    due_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('todo', 'done')),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_tasks_assigned ON tasks(assigned_to);
CREATE INDEX idx_tasks_due_at ON tasks(due_at);
CREATE INDEX idx_tasks_status ON tasks(status);

-- =============================================================================
-- DỮ LIỆU MẪU (SEED DATA - 100% HƯ CẤU)
-- =============================================================================

-- 1. USERS: 5 tài khoản mẫu (password_hash='!PENDING' để bootstrap tự đổi)
INSERT INTO users (username, email, password_hash, full_name, role, is_active, created_at) VALUES
('admin',     'admin@example.com',     '!PENDING', 'Nguyễn Quản Trị',   'manager', true, NOW() - INTERVAL '90 days'),
('sales01',   'sales01@example.com',   '!PENDING', 'Trần Kinh Doanh',   'sales',   true, NOW() - INTERVAL '90 days'),
('sales02',   'sales02@example.com',   '!PENDING', 'Lê Bán Hàng',       'sales',   true, NOW() - INTERVAL '80 days'),
('support01', 'support01@example.com', '!PENDING', 'Phạm Chăm Sóc',     'support', true, NOW() - INTERVAL '90 days'),
('support02', 'support02@example.com', '!PENDING', 'Vũ Hỗ Trợ',         'support', true, NOW() - INTERVAL '70 days');

-- 2. CUSTOMERS: 20 khách hàng đủ 4 phân khúc và các nguồn tiếp cận
INSERT INTO customers (customer_code, full_name, company, email, phone, address, source, segment, owner_id, notes, is_archived, created_at, updated_at) VALUES
('KH0001', 'Nguyễn Văn An',     'Công ty TNHH Sao Mai',       'an.nguyen@example.com',    '0901000001', '12 Nguyễn Trãi, Thanh Xuân, Hà Nội',       'website',   'vip',      2, 'Khách hàng thân thiết từ 2024, doanh số lớn', false, NOW() - INTERVAL '60 days', NOW() - INTERVAL '5 days'),
('KH0002', 'Lê Thị Bình',       'Công ty CP Đầu Tư An Bình',  'binh.le@example.com',      '0901000002', '45 Lê Duẩn, Quận 1, TP. Hồ Chí Minh',      'referral',  'vip',      3, 'Chu kỳ thanh toán nhanh, cần chăm sóc định kỳ', false, NOW() - INTERVAL '55 days', NOW() - INTERVAL '2 days'),
('KH0003', 'Trần Hữu Cường',    'Tập đoàn Công nghệ Alpha',   'cuong.tran@example.com',   '0901000003', '78 Cầu Giấy, Cầu Giấy, Hà Nội',            'event',     'regular',  2, 'Quan tâm gói CRM mở rộng tích hợp API', false, NOW() - INTERVAL '50 days', NOW() - INTERVAL '10 days'),
('KH0004', 'Phạm Minh Đức',     'Công ty Cơ Khí Hoàng Gia',   'duc.pham@example.com',     '0901000004', '15 Quang Trung, Hải Châu, Đà Nẵng',         'facebook',  'regular',  3, 'Đang dùng thử 3 tháng', false, NOW() - INTERVAL '45 days', NOW() - INTERVAL '12 days'),
('KH0005', 'Hoàng Thu Dung',    'Công ty Dược phẩm Đông Á',   'dung.hoang@example.com',   '0901000005', '88 Hai Bà Trưng, Quận 3, TP. Hồ Chí Minh',  'cold_call', 'regular',  2, 'Cần đào tạo thêm nhân sự sử dụng hệ thống', false, NOW() - INTERVAL '40 days', NOW() - INTERVAL '8 days'),
('KH0006', 'Vũ Quốc Hùng',      'Công ty Logistics Tân Cảng', 'hung.vu@example.com',      '0901000006', '102 Nguyễn Huệ, Quận 1, TP. Hồ Chí Minh',   'website',   'new',      3, 'Mới đăng ký tư vấn qua landing page', false, NOW() - INTERVAL '5 days', NOW() - INTERVAL '1 days'),
('KH0007', 'Đặng Thảo Lan',     'Học Viện Đào Tạo Kỹ Năng',   'lan.dang@example.com',     '0901000007', '34 Trần Hưng Đạo, Hoàn Kiếm, Hà Nội',       'facebook',  'new',      2, 'Đăng ký nhận báo giá phần mềm quản lý học viên', false, NOW() - INTERVAL '8 days', NOW() - INTERVAL '2 days'),
('KH0008', 'Bùi Xuân Mai',      'Nội Thất Hiện Đại SkyHome',  'mai.bui@example.com',      '0901000008', '56 Nguyễn Thị Minh Khai, TP. Nha Trang',     'event',     'new',      3, 'Gặp tại hội chợ triển lãm VietBuild', false, NOW() - INTERVAL '12 days', NOW() - INTERVAL '4 days'),
('KH0009', 'Đỗ Thanh Nam',      'Công ty Nông Sản Hưng Thịnh','nam.do@example.com',       '0901000009', '72 Hùng Vương, TP. Buôn Ma Thuột',          'referral',  'inactive', 2, 'Tạm ngưng dự án do tái cơ cấu doanh nghiệp', false, NOW() - INTERVAL '80 days', NOW() - INTERVAL '20 days'),
('KH0010', 'Ngô Diễm Quỳnh',    'Thời Trang Quốc Tế Chic',    'quynh.ngo@example.com',    '0901000010', '90 Phố Huế, Hai Bà Trưng, Hà Nội',          'other',     'inactive', 3, 'Chưa có nhu cầu gia hạn', false, NOW() - INTERVAL '90 days', NOW() - INTERVAL '30 days'),
('KH0011', 'Dương Tuấn Khang',  'Công ty CP Bất Động Sản Á',  'khang.duong@example.com',  '0901000011', '14 Láng Hạ, Đống Đa, Hà Nội',               'website',   'vip',      2, 'Khách hàng trọng điểm, hợp đồng dài hạn', false, NOW() - INTERVAL '35 days', NOW() - INTERVAL '1 days'),
('KH0012', 'Lý Hải Long',       'Chuỗi Nhà Hàng Biển Xanh',   'long.ly@example.com',      '0901000012', '200 Võ Nguyên Giáp, TP. Đà Nẵng',           'referral',  'regular',  3, 'Cần kết nối POS với CRM', false, NOW() - INTERVAL '28 days', NOW() - INTERVAL '3 days'),
('KH0013', 'Mai Phương Nga',    'Công ty Mỹ Phẩm Sài Gòn',    'nga.mai@example.com',      '0901000013', '67 Cách Mạng Tháng 8, Quận 10, TP. HCM',     'facebook',  'regular',  2, 'Kênh phân phối đang mở rộng', false, NOW() - INTERVAL '25 days', NOW() - INTERVAL '7 days'),
('KH0014', 'Hồ Quang Phúc',     'Vận Tải Hành Khách Đại Nam', 'phuc.ho@example.com',      '0901000014', '12 Bến Xe Miền Đông, Bình Thạnh, TP. HCM',   'cold_call', 'new',      3, 'Đang gửi bản demo chức năng', false, NOW() - INTERVAL '6 days', NOW() - INTERVAL '1 days'),
('KH0015', 'Phan Thanh Sơn',    'Công ty Thiết Bị Y Tế Việt', 'son.phan@example.com',     '0901000015', '84 Giải Phóng, Hai Bà Trưng, Hà Nội',        'event',     'new',      2, 'Quan tâm bảo mật dữ liệu y tế', false, NOW() - INTERVAL '4 days', NOW() - INTERVAL '1 days'),
('KH0016', 'Tạ Thu Trang',      'Công ty Du Lịch Á Châu',     'trang.ta@example.com',     '0901000016', '18 Lý Thường Kiệt, TP. Huế',                 'website',   'regular',  3, 'Cần tích hợp email marketing', false, NOW() - INTERVAL '30 days', NOW() - INTERVAL '9 days'),
('KH0017', 'Vương Đình Trọng',  'In Ấn & Bao Bì Toàn Cầu',    'trong.vuong@example.com',  '0901000017', '49 Điện Biên Phủ, TP. Hải Phòng',            'referral',  'inactive', 2, 'Hết ngân sách năm 2026', false, NOW() - INTERVAL '75 days', NOW() - INTERVAL '25 days'),
('KH0018', 'Đoàn Yến Vy',       'Trung Tâm Thể Hình FitLife', 'vy.doan@example.com',      '0901000018', '110 Hoàng Diệu, TP. Cần Thơ',                'facebook',  'regular',  3, 'Tương tác tốt, chuẩn bị tái ký', false, NOW() - INTERVAL '22 days', NOW() - INTERVAL '3 days'),
('KH0019', 'Lâm Gia Bách',      'Công ty Bán Lẻ Siêu Việt',   'bach.lam@example.com',     '0901000019', '23 Phan Đăng Lưu, Phú Nhuận, TP. HCM',      'other',     'vip',      2, 'Quy mô 500 nhân sự', false, NOW() - INTERVAL '40 days', NOW() - INTERVAL '2 days'),
('KH0020', 'Châu Mỹ Uyên',      'Công ty Cổ Phần Xuất Nhập',  'uyen.chau@example.com',    '0901000020', '95 Lê Lợi, TP. Vũng Tàu',                    'cold_call', 'inactive', 3, 'Khách hàng tạm đóng băng hoạt động', true, NOW() - INTERVAL '85 days', NOW() - INTERVAL '15 days');

-- Cập nhật sequence khách hàng
SELECT setval('customers_code_seq', 20);

-- 3. INTERACTIONS: 25 tương tác đa dạng kênh
INSERT INTO interactions (customer_id, user_id, type, subject, content, occurred_at, created_at) VALUES
(1, 2, 'meeting', 'Họp rà soát tiến độ triển khai', 'Trao đổi với anh An về kế hoạch triển khai giai đoạn 2.', NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days'),
(1, 2, 'call',    'Gọi điện chăm sóc định kỳ', 'Khách hàng hài lòng với hệ thống CRM, chưa có phàn nàn gì.', NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days'),
(1, 2, 'note',    'Ghi chú hợp đồng VIP', 'Lưu ý chính sách giảm giá 10% khi tái ký hợp đồng năm tới.', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
(2, 3, 'call',    'Tư vấn nâng cấp license', 'Chị Bình có nhu cầu thêm 15 tài khoản sales cho chi nhánh mới.', NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days'),
(2, 3, 'meeting', 'Ký phụ lục hợp đồng', 'Đã ký phụ lục nâng cấp lên gói Enterprise tại văn phòng khách.', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days'),
(2, 3, 'email',   'Gửi tài liệu hướng dẫn API', 'Đã đính kèm tài liệu kết nối CRM với hệ thống ERP SAP.', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
(3, 2, 'email',   'Gửi bản báo giá chính thức', 'Gửi báo giá bản quyền vĩnh viễn và chi phí bảo trì năm.', NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days'),
(3, 2, 'call',    'Thảo luận chiết khấu', 'Anh Cường đề xuất chiết khấu thanh toán một lần 5%.', NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days'),
(4, 3, 'call',    'Hỏi thăm sử dụng bản thử nghiệm', 'Khách phản hồi giao diện dễ dùng nhưng cần thêm báo cáo excel.', NOW() - INTERVAL '25 days', NOW() - INTERVAL '25 days'),
(4, 3, 'chat',    'Hỗ trợ qua Zalo OA', 'Hướng dẫn khách cấu hình gửi email tự động.', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days'),
(5, 2, 'meeting', 'Đào tạo nhân sự nội bộ', 'Tổ chức buổi workshop 2 giờ cho 8 nhân viên CSKH Đông Á.', NOW() - INTERVAL '22 days', NOW() - INTERVAL '22 days'),
(6, 3, 'call',    'Cuộc gọi đầu tiên sau khi đăng ký', 'Xác nhận thông tin nhu cầu: Cần quản lý 1000 khách vận tải.', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days'),
(6, 3, 'email',   'Gửi brochure và video giới thiệu', 'Gửi link demo và tài liệu tính năng CRM logistics.', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'),
(7, 2, 'chat',    'Tư vấn trực tuyến qua Facebook', 'Giải đáp thắc mắc về chi phí triển khai cho học viện.', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days'),
(8, 3, 'meeting', 'Gặp gỡ trực tiếp tại gian hàng', 'Khách ghé thăm booth tại triển lãm và để lại thông tin liên hệ.', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days'),
(9, 2, 'call',    'Liên hệ lại sau thời gian im lặng', 'Anh Nam thông báo công ty đang chờ duyệt ngân sách quý mới.', NOW() - INTERVAL '40 days', NOW() - INTERVAL '40 days'),
(11, 2, 'meeting','Thương thảo hợp đồng chiến lược', 'Họp với ban giám đốc BĐS Á Châu về việc số hóa quản lý sàn.', NOW() - INTERVAL '28 days', NOW() - INTERVAL '28 days'),
(11, 2, 'email',  'Gửi dự thảo hợp đồng 2 năm', 'Dự thảo đã được phòng pháp chế kiểm duyệt.', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),
(12, 3, 'call',   'Khảo sát hạ tầng POS chuỗi', 'Trao đổi với IT chuỗi nhà hàng về cổng kết nối webhook.', NOW() - INTERVAL '14 days', NOW() - INTERVAL '14 days'),
(13, 2, 'email',  'Chúc mừng sinh nhật công ty', 'Gửi thư chúc mừng và mã ưu đãi giảm 15% gói gia hạn.', NOW() - INTERVAL '16 days', NOW() - INTERVAL '16 days'),
(14, 3, 'call',   'Hẹn lịch demo giải pháp', 'Chốt lịch demo online qua Google Meet vào thứ Sáu tuần này.', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
(15, 2, 'meeting','Họp bảo mật thông tin', 'Thống nhất tiêu chuẩn mã hóa dữ liệu bệnh nhân và khách hàng y tế.', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'),
(16, 3, 'chat',   'Trao đổi mẫu email template', 'Khách hàng gửi mẫu thư quảng bá tour du lịch để import CRM.', NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days'),
(18, 3, 'call',   'Khảo sát mức độ hài lòng', 'Điểm CSAT 9/10, đề xuất thêm chức năng điểm danh QR Code.', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
(19, 2, 'meeting','Ký kết thỏa thuận hợp tác đối tác', 'Thống nhất hợp tác toàn diện với Siêu Việt trong 3 năm.', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days');

-- 4. OPPORTUNITIES: 10 cơ hội bán hàng phân bổ đủ các giai đoạn
INSERT INTO opportunities (customer_id, title, value, stage, probability, expected_close, owner_id, lost_reason, created_at, closed_at) VALUES
(1,  'Gia hạn hợp đồng dịch vụ CRM Premium 2026',        120000000, 'won',       100, (CURRENT_DATE - INTERVAL '10 days')::DATE, 2, NULL,                             NOW() - INTERVAL '50 days', NOW() - INTERVAL '10 days'),
(2,  'Gói nâng cấp 15 License Enterprise & Tích hợp SAP', 180000000, 'won',       100, (CURRENT_DATE - INTERVAL '5 days')::DATE,  3, NULL,                             NOW() - INTERVAL '40 days', NOW() - INTERVAL '5 days'),
(3,  'Triển khai bản quyền CRM vĩnh viễn Alpha Tech',     250000000, 'proposal',  75,  (CURRENT_DATE + INTERVAL '15 days')::DATE, 2, NULL,                             NOW() - INTERVAL '30 days', NULL),
(4,  'Gói thuê bao Cloud CRM Standard 1 năm Hoàng Gia',    45000000, 'qualified', 50,  (CURRENT_DATE + INTERVAL '25 days')::DATE, 3, NULL,                             NOW() - INTERVAL '20 days', NULL),
(5,  'Module quản lý kho & CSKH Dược Phẩm Đông Á',         85000000, 'contacted', 25,  (CURRENT_DATE + INTERVAL '30 days')::DATE, 2, NULL,                             NOW() - INTERVAL '15 days', NULL),
(6,  'Triển khai hệ thống CRM quản lý vận tải Tân Cảng',   150000000, 'new',       10,  (CURRENT_DATE + INTERVAL '45 days')::DATE, 3, NULL,                             NOW() - INTERVAL '5 days',  NULL),
(7,  'Hệ thống quản lý học viên Đào Tạo Kỹ Năng',          35000000, 'new',       10,  (CURRENT_DATE + INTERVAL '40 days')::DATE, 2, NULL,                             NOW() - INTERVAL '7 days',  NULL),
(8,  'Gói phần mềm CRM SkyHome 6 tháng',                   28000000, 'contacted', 25,  (CURRENT_DATE + INTERVAL '20 days')::DATE, 3, NULL,                             NOW() - INTERVAL '11 days', NULL),
(9,  'Triển khai CRM cho chuỗi nông sản Hưng Thịnh',       95000000, 'lost',        0,  (CURRENT_DATE - INTERVAL '15 days')::DATE, 2, 'Khách hàng cắt giảm ngân sách',  NOW() - INTERVAL '60 days', NOW() - INTERVAL '15 days'),
(10, 'Phần mềm quản lý chuỗi thời trang Chic Boutique',    60000000, 'lost',        0,  (CURRENT_DATE - INTERVAL '20 days')::DATE, 3, 'Chọn nhà cung cấp khác giá rẻ', NOW() - INTERVAL '70 days', NOW() - INTERVAL '20 days');

-- 5. TICKETS: 10 ticket đủ trạng thái, mức ưu tiên và SLA
-- Lưu ý: SLA logic: urgent=4h, high=8h, medium=24h, low=72h
INSERT INTO tickets (ticket_code, customer_id, created_by, assigned_to, subject, description, category, priority, status, created_at, updated_at, resolved_at) VALUES
('TK-20261015-0001', 1, 2, 4, 'Không gửi được email tự động khi chốt đơn', 'Hệ thống báo lỗi SMTP timeout khi trigger chiến dịch gửi email.', 'technical', 'urgent', 'open',        NOW() - INTERVAL '6 hours',  NOW() - INTERVAL '1 hours',  NULL),
('TK-20261016-0002', 2, 3, 5, 'Sai lệch số liệu báo cáo xuất file Excel',  'Cột tổng doanh thu trong file Excel bị lệch 5% so với hiển thị trên web.', 'billing',   'high',   'in_progress', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '2 hours',  NULL),
('TK-20261017-0003', 3, 2, 4, 'Yêu cầu mở rộng giới hạn API Rate Limit',   'Hệ thống ERP của khách bị chặn do vượt quá 100 requests/phút.', 'consulting', 'medium', 'open',        NOW() - INTERVAL '30 hours', NOW() - INTERVAL '5 hours',  NULL),
('TK-20261018-0004', 4, 3, 5, 'Lỗi hiển thị font chữ tiếng Việt trên app',  'Menu danh mục bị vỡ font khi truy cập bằng trình duyệt Safari.', 'technical', 'low',    'open',        NOW() - INTERVAL '80 hours', NOW() - INTERVAL '10 hours', NULL),
('TK-20261012-0005', 5, 2, 4, 'Khiếu nại về tốc độ phản hồi tổng đài',     'Khách hàng phản ánh gọi hotline 3 lần không có nhân viên bắt máy.', 'complaint', 'high',   'resolved',    NOW() - INTERVAL '3 days',    NOW() - INTERVAL '1 days',   NOW() - INTERVAL '1 days'),
('TK-20261010-0006', 1, 3, 5, 'Cần xuất hóa đơn VAT điện tử tháng 9',       'Thông tin MST công ty thay đổi, cần cập nhật để xuất lại hóa đơn.', 'billing',   'medium', 'closed',      NOW() - INTERVAL '7 days',    NOW() - INTERVAL '4 days',   NOW() - INTERVAL '4 days'),
('TK-20261019-0007', 6, 3, 4, 'Tài khoản nhân viên sales mới không đăng nhập được', 'Báo lỗi tài khoản chưa kích hoạt sau khi admin tạo.', 'technical', 'urgent', 'in_progress', NOW() - INTERVAL '2 hours',  NOW() - INTERVAL '30 mins',  NULL),
('TK-20261019-0008', 7, 2, 5, 'Hỏi về quy trình sao lưu dữ liệu tự động',  'Khách muốn biết dữ liệu lưu trên cloud hay on-premise.', 'consulting', 'low',    'in_progress', NOW() - INTERVAL '5 hours',  NOW() - INTERVAL '1 hours',  NULL),
('TK-20261014-0009', 11,2, 4, 'Lỗi tải tệp hợp đồng đính kèm kích thước lớn', 'File PDF scan 5MB không tải lên được vào mục tương tác.', 'technical', 'medium', 'resolved',    NOW() - INTERVAL '4 days',    NOW() - INTERVAL '2 days',   NOW() - INTERVAL '2 days'),
('TK-20261013-0010', 12,3, 5, 'Yêu cầu tích hợp thêm cổng thanh toán VNPay', 'Chuỗi nhà hàng muốn thanh toán trực tiếp qua mã QR VNPay.', 'other',     'high',   'closed',      NOW() - INTERVAL '6 days',    NOW() - INTERVAL '3 days',   NOW() - INTERVAL '3 days');

SELECT setval('ticket_code_seq', 10);

-- 6. TICKET COMMENTS: Bình luận trao đổi hỗ trợ
INSERT INTO ticket_comments (ticket_id, user_id, content, attachment_path, attachment_name, created_at) VALUES
(1, 4, 'Đã tiếp nhận ticket. Kỹ thuật đang kiểm tra cổng kết nối SMTP máy chủ mail.', NULL, NULL, NOW() - INTERVAL '5 hours'),
(1, 2, 'Khách hàng đang cần gấp để gửi thông báo khuyến mãi sáng nay.', NULL, NULL, NOW() - INTERVAL '4 hours'),
(2, 5, 'Đã tái hiện được lỗi tính tổng khi có đơn hàng được giảm giá đặc biệt.', NULL, NULL, NOW() - INTERVAL '10 hours'),
(2, 5, 'Đang cập nhật câu truy vấn SUM() và kiểm tra lại module export.', NULL, NULL, NOW() - INTERVAL '4 hours'),
(5, 4, 'Đã liên hệ trực tiếp xin lỗi khách hàng và bổ sung thêm 2 line trực hotline.', NULL, NULL, NOW() - INTERVAL '2 days'),
(7, 4, 'Đã kích hoạt lại cờ is_active cho tài khoản nhân viên. Nhờ anh đăng nhập thử lại.', NULL, NULL, NOW() - INTERVAL '1 hours');

-- 7. TASKS: 12 nhắc việc đủ các trạng thái và thời hạn
INSERT INTO tasks (title, description, customer_id, assigned_to, created_by, due_at, status, created_at, completed_at) VALUES
('Gọi điện chúc mừng sinh nhật anh An (Sao Mai)', 'Chuẩn bị quà lưu niệm công ty gửi tận nơi.', 1, 2, 1, NOW() - INTERVAL '2 hours', 'done', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 hours'),
('Chuẩn bị tài liệu thuyết trình cho Alpha Tech', 'Soạn slide chuyên sâu về bảo mật và API.', 3, 2, 1, NOW() - INTERVAL '5 hours', 'todo', NOW() - INTERVAL '2 days', NULL),
('Gửi hợp đồng nâng cấp license cho chị Bình', 'Soạn thảo bản in và gửi chuyển phát nhanh.', 2, 3, 1, NOW() - INTERVAL '1 days', 'todo', NOW() - INTERVAL '4 days', NULL),
('Demo trực tuyến giải pháp cho Logistics Tân Cảng', 'Chuẩn bị phòng họp Google Meet và tài liệu vận tải.', 6, 3, 1, NOW() + INTERVAL '2 hours', 'todo', NOW() - INTERVAL '1 days', NULL),
('Kiểm tra phản hồi báo giá Học Viện Kỹ Năng', 'Gọi điện hỏi thăm cô Lan về mức ngân sách đề xuất.', 7, 2, 1, NOW() + INTERVAL '4 hours', 'todo', NOW() - INTERVAL '2 days', NULL),
('Liên hệ khách hàng SkyHome khảo sát lại nhu cầu', 'Xem khách đã hoàn tất chọn mặt bằng showroom chưa.', 8, 3, 1, NOW() + INTERVAL '8 hours', 'todo', NOW() - INTERVAL '3 days', NULL),
('Họp nội bộ rà soát tỷ lệ chuyển đổi tuần này', 'Chuẩn bị báo cáo doanh số cho anh Dũng (Manager).', NULL, 2, 1, NOW() + INTERVAL '2 days', 'todo', NOW() - INTERVAL '1 days', NULL),
('Kiểm tra hạ tầng server định kỳ quý 4', 'Đo lường dung lượng ổ đĩa và hiệu năng PostgreSQL.', NULL, 4, 1, NOW() + INTERVAL '3 days', 'todo', NOW() - INTERVAL '4 days', NULL),
('Hỗ trợ kết nối API cho bên thứ ba của BĐS Á Châu', 'Cung cấp token test và tài liệu sandbox.', 11, 4, 1, NOW() + INTERVAL '5 days', 'todo', NOW() - INTERVAL '2 days', NULL),
('Đào tạo nhân viên support mới về quy trình SLA', 'Phổ biến thời gian cam kết theo cấp độ ưu tiên ticket.', NULL, 5, 1, NOW() + INTERVAL '6 days', 'todo', NOW() - INTERVAL '3 days', NULL),
('Thu hồi tài khoản dùng thử quá hạn 30 ngày', 'Lọc danh sách các tài khoản khách hàng chưa gia hạn.', NULL, 4, 1, NOW() - INTERVAL '1 days', 'done', NOW() - INTERVAL '5 days', NOW() - INTERVAL '1 days'),
('Cập nhật mẫu biên bản nghiệm thu phần mềm 2026', 'Thêm điều khoản cam kết bảo mật thông tin.', NULL, 3, 1, NOW() - INTERVAL '3 days', 'done', NOW() - INTERVAL '7 days', NOW() - INTERVAL '3 days');



-- 8. TÀI KHOẢN GIÁM SÁT PROMETHEUS POSTGRES EXPORTER (Quyền tối thiểu pg_monitor)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'exporter') THEN
    CREATE USER exporter WITH LOGIN PASSWORD 'exporter_password_configured_via_env';
    GRANT pg_monitor TO exporter;
  END IF;
END
$$;
