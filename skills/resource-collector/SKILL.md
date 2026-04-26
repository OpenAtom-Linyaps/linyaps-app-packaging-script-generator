---
name: resource-collector
description: '从deb解压目录收集资源文件(desktop、icons、appdata等)并整理到files_res目录。Use when: 需要提取应用资源、整理desktop文件、收集图标文件、验证资源合规性。'
argument-hint: 'deb解压路径和目标工程目录'
---

# 资源收集器

## 功能说明

从deb包解压后的目录中提取应用资源文件（desktop文件、图标、appdata、补全脚本等），按照玲珑打包规范整理到 `files_res/` 目录结构中。

## 触发场景

- 需要从deb中提取desktop文件
- 需要收集应用图标
- 需要整理资源文件到规范目录结构
- 需要验证资源文件合规性

## 工作流程

### 1. 扫描资源文件

从deb解压目录扫描各类资源：

```python
import os
from pathlib import Path

def scan_resources(data_path: str) -> dict:
    """扫描deb解压目录中的资源文件"""
    resources = {
        'desktop_files': [],
        'icons': [],
        'appdata': [],
        'mime': [],
        'bash_completion': [],
        'zsh_completion': [],
        'pixmaps': [],
        'binaries': []
    }
    
    data_dir = Path(data_path)
    
    # 扫描desktop文件
    for f in data_dir.rglob('*.desktop'):
        if 'applications' in str(f):
            resources['desktop_files'].append(str(f))
    
    # 扫描图标
    for ext in ['*.png', '*.svg', '*.svgz', '*.jpg', '*.xpm']:
        for f in data_dir.rglob(ext):
            if 'icons' in str(f) or 'pixmaps' in str(f):
                resources['icons'].append(str(f))
    
    # 扫描appdata/metainfo
    for f in data_dir.rglob('*.appdata.xml'):
        resources['appdata'].append(str(f))
    for f in data_dir.rglob('*.metainfo.xml'):
        resources['appdata'].append(str(f))
    
    # 扫描MIME类型定义
    for f in data_dir.rglob('*.xml'):
        if 'mime' in str(f):
            resources['mime'].append(str(f))
    
    # 扫描补全脚本
    for f in data_dir.rglob('*'):
        if 'bash-completion' in str(f):
            resources['bash_completion'].append(str(f))
        if 'zsh' in str(f) and 'vendor-completions' in str(f):
            resources['zsh_completion'].append(str(f))
    
    return resources
```

### 2. 整理到 files_res 目录

按照FHS规范整理资源：

```bash
# 目标目录结构
files_res/
└── share/
    ├── applications/           # desktop文件
    │   └── com.example.app.desktop
    ├── icons/                  # 图标
    │   └── hicolor/
    │       ├── 48x48/apps/
    │       ├── 256x256/apps/
    │       └── scalable/apps/
    ├── appdata/                # 应用数据
    │   └── com.example.app.appdata.xml
    ├── mime/                   # MIME类型
    │   └── packages/
    ├── bash-completion/        # Bash补全
    │   └── completions/
    ├── zsh/                    # Zsh补全
    │   └── vendor-completions/
    └── pixmaps/                # 像素图
```

### 3. 复制资源文件

```python
import shutil
from pathlib import Path

def copy_resources(resources: dict, target_dir: str, package_id: str):
    """复制资源文件到目标目录"""
    share_dir = Path(target_dir) / 'share'
    
    # 复制desktop文件
    for src in resources['desktop_files']:
        dst = share_dir / 'applications' / Path(src).name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        # 修改desktop文件中的Icon和Exec路径
        fix_desktop_file(dst, package_id)
    
    # 复制图标
    for src in resources['icons']:
        # 保持相对路径结构
        rel_path = extract_icon_relative_path(src)
        dst = share_dir / 'icons' / rel_path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    
    # 复制appdata
    for src in resources['appdata']:
        dst = share_dir / 'appdata' / f'{package_id}.appdata.xml'
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    
    # 复制其他资源...
```

### 4. 修复desktop文件

```python
def fix_desktop_file(desktop_path: str, package_id: str):
    """修复desktop文件中的路径，使其符合玲珑规范"""
    with open(desktop_path, 'r') as f:
        content = f.read()
    
    # 修复Icon路径为相对路径
    # Icon=/usr/share/icons/xxx -> Icon=xxx
    content = re.sub(r'Icon=/.*?/([^/]+)\.(png|svg)', r'Icon=\1', content)
    
    # 修复Exec路径为相对路径
    # 玲珑规范要求使用相对路径，二进制软链由pak_linyaps.sh处理
    # Exec=/usr/bin/app %F -> Exec=app %F
    # Exec=/opt/apps/com.example/files/bin/app/app %F -> Exec=app %F
    content = re.sub(r'Exec=/[^ ]*?/([^/]+)(\s|$)', r'Exec=\1\2', content)
    
    with open(desktop_path, 'w') as f:
        f.write(content)
```

**注意：**
- desktop文件的Exec字段必须使用相对路径（如 `Exec=code %F`）
- 二进制文件由 `pak_linyaps.sh` 在构建时软链到 `${prefix}/bin/`
- `linglong.yaml` 的 `command` 字段也应使用相对路径（如 `command: ["code"]`）

### 5. 验证资源合规性

调用 `common-data-verify.py` 验证：

```bash
python3 common-data-verify.py <files_res_dir> --json --output report.json
```

验证项：
- desktop文件Icon/Exec使用相对路径
- 图标目录结构符合规范
- 图标格式一致性
- 二进制文件可执行

## 输出数据结构

```json
{
  "status": "success",
  "target_dir": "CI_ll_com.example.app/templates/files_res",
  "collected": {
    "desktop_files": 1,
    "icons": 12,
    "appdata": 1,
    "mime": 1,
    "bash_completion": 1,
    "zsh_completion": 1
  },
  "validation": {
    "passed": true,
    "checks": {
      "desktop_files": {"status": "passed", "details": []},
      "icons": {"status": "passed", "details": []},
      "binaries": {"status": "passed", "details": []}
    }
  }
}
```

## 资源映射规则

| deb路径 | files_res路径 | 说明 |
|--------|--------------|------|
| `usr/share/applications/*.desktop` | `share/applications/` | desktop文件 |
| `usr/share/icons/hicolor/*/apps/*` | `share/icons/hicolor/*/apps/` | 图标 |
| `usr/share/pixmaps/*` | `share/pixmaps/` | 像素图 |
| `usr/share/metainfo/*.xml` | `share/appdata/` | 应用数据 |
| `usr/share/mime/packages/*` | `share/mime/packages/` | MIME定义 |
| `usr/share/bash-completion/completions/*` | `share/bash-completion/completions/` | Bash补全 |
| `usr/share/zsh/vendor-completions/*` | `share/zsh/vendor-completions/` | Zsh补全 |

## 注意事项

1. desktop文件必须修复Icon和Exec为相对路径
2. 图标目录结构必须符合hicolor规范
3. appdata文件重命名为 `{package_id}.appdata.xml`
4. 验证失败时记录问题，等待修复skill处理
5. 保留原始文件权限和符号链接
