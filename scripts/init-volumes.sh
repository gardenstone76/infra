#!/bin/bash

# 공유 인프라 Docker 볼륨 디렉토리 초기화 스크립트
# 최초 1회 실행 필요

set -e

echo "Creating shared infra volume directories..."

# MySQL
MYSQL_PATH="/var/lib/docker-data/shared/mysql"
if [ -d "$MYSQL_PATH" ]; then
    echo "✓ $MYSQL_PATH already exists"
else
    sudo mkdir -p "$MYSQL_PATH"
    sudo chmod 755 "$MYSQL_PATH"
    sudo chown -R 999:999 "$MYSQL_PATH"
    echo "✓ Created $MYSQL_PATH"
fi

echo ""
echo "Done! Now run: docker compose up -d"
