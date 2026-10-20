const express = require('express');
const session = require('express-session');
const path = require('path');
const db = require('./db');
const bootstrapPasswords = require('./scripts/bootstrap-passwords');
const csrfMiddleware = require('./middlewares/csrf');

const authRoutes = require('./routes/auth');
const dashboardRoutes = require('./routes/dashboard');
const customerRoutes = require('./routes/customers');
const interactionRoutes = require('./routes/interactions');
const opportunityRoutes = require('./routes/opportunities');
const ticketRoutes = require('./routes/tickets');
const taskRoutes = require('./routes/tasks');
const userRoutes = require('./routes/users');

const app = express();
const PORT = process.env.PORT || 3000;

// Bảo mật cơ bản: Tắt X-Powered-By và tin cậy proxy (phục vụ Nginx sau này)
app.disable('x-powered-by');
app.set('trust proxy', 1);

// Cấu hình View Engine (EJS)
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '../views'));

// Phục vụ tệp tĩnh (CSS, JS)
app.use(express.static(path.join(__dirname, '../public')));

// Parse form body và JSON (giới hạn 1MB)
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));

// Thiết lập trust proxy để express-session nhận diện đúng kết nối HTTPS qua Nginx
app.set('trust proxy', 1);

// Kiểm tra nghiêm ngặt biến môi trường SESSION_SECRET (không dùng giá trị dự phòng, tối thiểu 32 ký tự)
const sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret || sessionSecret.trim().length < 32) {
  console.error('[FATAL] SESSION_SECRET is missing or shorter than 32 characters. Aborting start.');
  process.exit(1);
}

// Quản lý phiên làm việc (Session)
app.use(session({
  name: 'crm_session',
  secret: sessionSecret,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'strict',
    secure: true, // Cố định true: chỉ truyền cookie qua HTTPS
    maxAge: 24 * 60 * 60 * 1000 // 24 giờ
  }
}));

// Điểm kiểm tra sức khỏe ứng dụng (Healthcheck) - Không yêu cầu CSRF
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Middleware toàn cục cho view templates
app.use((req, res, next) => {
  res.locals.currentUser = req.session ? req.session.user : null;
  res.locals.currentPath = req.path;
  next();
});

// Kiểm tra CSRF token cho các phương thức POST/PUT/DELETE
app.use(csrfMiddleware);

// Đăng ký các Route nghiệp vụ
app.use('/auth', authRoutes);
app.use('/dashboard', dashboardRoutes);
app.use('/customers', customerRoutes);
app.use('/interactions', interactionRoutes);
app.use('/opportunities', opportunityRoutes);
app.use('/tickets', ticketRoutes);
app.use('/tasks', taskRoutes);
app.use('/users', userRoutes);

// Trang chủ chuyển hướng đến Dashboard
app.get('/', (req, res) => {
  res.redirect('/dashboard');
});

// Xử lý 404 Not Found
app.use((req, res) => {
  res.status(404).render('error', {
    title: '404 - Không tìm thấy trang',
    status: 404,
    message: 'Trang hoặc tài nguyên bạn tìm kiếm không tồn tại trên hệ thống CRM.'
  });
});

// Xử lý lỗi tập trung 500
app.use((err, req, res, next) => {
  console.error('[App Error]', err);
  res.status(500).render('error', {
    title: '500 - Lỗi máy chủ',
    status: 500,
    message: err.message || 'Đã xảy ra lỗi không xác định trên hệ thống.'
  });
});

// Khởi động ứng dụng và Bootstrap CSDL
async function startServer() {
  let connected = false;
  for (let i = 0; i < 15; i++) {
    try {
      await db.query('SELECT 1');
      connected = true;
      console.log('[DB] Connected to PostgreSQL database successfully.');
      break;
    } catch (err) {
      console.log(`[DB] Waiting for database readiness... (${i + 1}/15)`);
      await new Promise(r => setTimeout(r, 2000));
    }
  }

  if (!connected) {
    console.error('[DB] Could not connect to PostgreSQL. Aborting start.');
    process.exit(1);
  }

  // Chạy bootstrap cập nhật mật khẩu cho các tài khoản seed
  await bootstrapPasswords();

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[Server] CRM Application is running on port ${PORT}`);
  });
}

startServer();
