const crypto = require('crypto');

function csrfMiddleware(req, res, next) {
  if (!req.session) {
    return next();
  }

  if (!req.session.csrfToken) {
    req.session.csrfToken = crypto.randomBytes(24).toString('hex');
  }

  res.locals.csrfToken = req.session.csrfToken;

  const method = req.method.toUpperCase();
  if (['GET', 'HEAD', 'OPTIONS'].includes(method)) {
    return next();
  }

  // Nếu là multipart/form-data, req.body chưa được parse bởi urlencoded.
  // Route handler có multer sẽ chịu trách nhiệm kiểm tra req.body._csrf sau khi parse.
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    const headerOrQueryToken = req.headers['x-csrf-token'] || req.headers['csrf-token'] || req.query?._csrf;
    if (headerOrQueryToken) {
      if (headerOrQueryToken !== req.session.csrfToken) {
        return res.status(403).send('Mã xác thực CSRF không hợp lệ.');
      }
    }
    return next();
  }

  const token = req.body?._csrf || req.headers['x-csrf-token'] || req.headers['csrf-token'] || req.query?._csrf;

  if (!token || token !== req.session.csrfToken) {
    if (req.xhr || req.headers.accept?.includes('application/json')) {
      return res.status(403).json({ error: 'Mã xác thực CSRF không hợp lệ hoặc phiên làm việc đã hết hạn.' });
    }
    return res.status(403).render('error', {
      title: 'Lỗi CSRF',
      status: 403,
      message: 'Mã xác thực CSRF không hợp lệ hoặc phiên làm việc đã hết hạn. Vui lòng tải lại trang và thử lại.'
    });
  }

  next();
}

module.exports = csrfMiddleware;
