#!/bin/bash
# 启动「个人工作台」本地 dev server（手机连电脑测试用）
# 用法：bash start-dev.sh
# 手机和电脑要连同一个 Wi-Fi。启动后 App 会自动找到电脑的局域网地址。
set -e
WB_DIR="/Users/hina/Documents/deepseek-harness/个人工作台"
cd "$WB_DIR"
echo "工作台目录：$WB_DIR"
IP=""
for i in en1 en0 en2 en3; do
  IP=$(ipconfig getifaddr $i 2>/dev/null || true)
  if [ -n "$IP" ]; then
    echo "本机局域网地址：http://$IP:3100"
    echo "手机和电脑请连同一个 Wi-Fi。App 会自动找到这个地址。"
    break
  fi
done
exec pnpm dev
