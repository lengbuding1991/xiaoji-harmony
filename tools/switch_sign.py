#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""切换 build-profile.json5 的签名配置。

用法:
    python3 tools/switch_sign.py agc     # 换成 DevEco 自动签名（华为 AGC 签发）——真机/上架用
    python3 tools/switch_sign.py local   # 换成 OpenHarmony 本地自签——模拟器用（真机不认）
    python3 tools/switch_sign.py show    # 只看当前是哪一种

为什么需要它：
  * 「agc」这条是 DevEco Studio 点一次「自动生成签名文件」写出来的，密码由 DevEco 自己加密，
    DevEco 的界面能正常打开它；真机和上架必须用这条。
  * 「local」这条是我们用 SDK 自带的 OpenHarmony.p12 现场签的，DevEco 的界面打不开它
    （会报「密钥库密码不正确」），所以只给模拟器用，装之前先切到 local。
"""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = ROOT / 'build-profile.json5'
SNAP = ROOT / 'tools' / 'signing'


def read_mode(text: str) -> str:
    return 'local' if 'local_workbench_' in text else 'agc'


def apply(mode: str) -> None:
    src = SNAP / ('profile-%s.json5' % mode)
    if not src.exists():
        print('缺少快照文件：%s' % src)
        sys.exit(1)
    text = src.read_text()
    if mode == 'local':
        mat = pathlib.Path.home() / '.ohos' / 'config'
        have = (mat / 'local_workbench_com.lbuding.workbench.p12').exists()
        if not have:
            print('本地签名材料不存在，正在生成 …')
            subprocess.run(['bash', str(ROOT / 'tools' / 'make_sign.sh')], check=False)
    shutil.copyfile(src, TARGET)
    print('已切换到 %s 模式（build-profile.json5）' % mode)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else 'show'
    if mode == 'show':
        print('当前签名配置：%s' % read_mode(TARGET.read_text()))
        return
    if mode in ('agc', 'local'):
        apply(mode)
        return
    print('参数只能是 agc / local / show')
    sys.exit(2)


if __name__ == '__main__':
    main()
