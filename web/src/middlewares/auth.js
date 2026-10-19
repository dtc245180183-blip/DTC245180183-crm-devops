function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }
  return req.socket?.remoteAddress || req.ip || '127.0.0.1';
}

function requireAuth(req, res, next) {
  if (req.session && req.session.user) {
    res.locals.currentUser = req.session.user;
    return next();
  }
  if (req.xhr || req.headers.accept?.includes('application/json')) {
    return res.status(401).json({ error: 'Vui lòng đăng nhập để tiếp tục.' });
  }
  return res.redirect('/auth/login');
}

function requireRole(...allowedRoles) {
  return (req, res, next) => {
    if (!req.session || !req.session.user) {
      if (req.xhr || req.headers.accept?.includes('application/json')) {
        return res.status(401).json({ error: 'Chưa đăng nhập.' });
      }
      return res.redirect('/auth/login');
    }

    const userRole = req.session.user.role;
    if (allowedRoles.includes(userRole)) {
      return next();
    }

    if (req.xhr || req.headers.accept?.includes('application/json')) {
      return res.status(403).json({ error: 'Bạn không có quyền thực hiện thao tác này.' });
    }
    return res.status(403).render('error', {
      title: 'Truy cập bị từ chối',
      status: 403,
      message: 'Bạn không có quyền truy cập chức năng này (Yêu cầu vai trò: ' + allowedRoles.join(', ') + ').'
    });
  };
}

module.exports = {
  getClientIp,
  requireAuth,
  requireRole,
};
