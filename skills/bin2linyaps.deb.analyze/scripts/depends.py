#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
depends.py - 运行时依赖存在性探测模块

本模块仅由 bin2linyaps.deb.analyze 内部使用（deb_to_linglong.py）。
供写入 buildext.apt.depends 前，逐包校验其是否真实存在于当前 apt 仓库。

判定标准：
    - 采用「单包」apt-cache show <pkg>，判定其 stdout 是否含 `Package:` 记录。
    - 不依赖 returncode（apt 2.8 下 LC_ALL=C 时缺失包也返回 0），
      也不依赖英文/本地化错误文案正则。
    - 单个包缺失时 stdout 为空且 rc=100；聚合调用（apt-cache show a b c）
      在部分缺失时 rc=0 且静默丢弃缺失包，故必须逐包调用。

其他 skill 禁止跨 skill import 本模块；如需同类校验，由 Agent/SKILL 编排
调用 bin2linyaps.deb.analyze 完成。
"""

import subprocess
import sys

__all__ = ["package_exists", "filter_existing_runtime_depends"]


def package_exists(pkg: str) -> bool:
    """单包独立校验 pkg 是否存在于当前 apt 仓库。以 stdout 出现 `Package:` 为准。"""
    if not pkg or not pkg.strip():
        return False
    try:
        result = subprocess.run(
            ["apt-cache", "show", pkg.strip().split()[0]],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        print(f"WARNING: 校验 {pkg} 存在性失败，按不可用处理: {e}", file=sys.stderr)
        return False
    # 缺失包 stdout 为空；可用包 stdout 以 "Package: <name>" 开头
    for line in result.stdout.splitlines():
        if line.startswith("Package:"):
            return True
    print(f"WARNING: 包 {pkg} 在当前 apt 仓库中不存在，已剔除", file=sys.stderr)
    return False


def filter_existing_runtime_depends(depends: list) -> list:
    """对运行时依赖列表逐包做存在性过滤，返回仅含真实可用包的列表。"""
    if not depends:
        return []
    available = []
    missing = []
    for pkg in depends:
        if package_exists(pkg):
            available.append(pkg)
        else:
            missing.append(pkg)
    if missing:
        print(
            f"WARNING: 以下 {len(missing)} 个运行时依赖在当前 apt 仓库不可用，"
            f"已自动过滤: {missing}",
            file=sys.stderr,
        )
    return available