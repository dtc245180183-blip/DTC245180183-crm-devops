FROM python:3.11.11-alpine
WORKDIR /app

# Tạo người dùng và nhóm không đặc quyền alertuser (UID/GID 1001)
RUN addgroup -g 1001 -S alertgroup && \
    adduser -u 1001 -S alertuser -G alertgroup

COPY --chown=alertuser:alertgroup server.py .

USER alertuser

EXPOSE 5001
CMD ["python", "-u", "server.py"]
