---
name: linglong-fix
description: '修复玲珑构建项目中的问题，使其通过各项检查。Use when: 验证失败需要修复、linglong.yaml格式问题、desktop文件路径问题、图标目录结构问题。'
argument-hint: '工程目录和验证报告'
---

# 玲珑工程修复

## 功能说明

根据验证报告自动修复玲珑构建项目中的问题，包括linglong.yaml格式、desktop文件、图标目录结构、二进制文件权限等。

## 触发场景

- linglong.yaml验证失败需要修复
- desktop文件路径不正确
- 图标目录结构不符合规范
- 二进制文件权限问题
- 兼容性检测发现问题

## 修复项清单

### 0. package_id 验证与修复

#### 0.1 验证 package_id

使用 `scripts/validate_package_id.sh` 验证 package_id 格式和一致性：

```bash
# 验证工程目录
./scripts/validate_package_id.sh CI_ll_com.visualstudio.code

# 验证工程目录和 deb 文件路径
./scripts/validate_package_id.sh CI_ll_com.visualstudio.code --deb-path com.visualstudio.code/code_1.85.0_amd64.deb

# 详细输出
./scripts/validate_package_id.sh CI_ll_com.visualstudio.code --verbose
```

**验证项：**
- 工程目录命名格式：`CI_ll_<package_id>`
- package_id 格式：反向域名格式（如 `com.example.app`）
- linglong.yaml 中的 `package.id` 与目录名一致性
- deb 文件存储路径：`<package_id>/xxx.deb`

**输出示例：**
```json
{
  "status": "passed",
  "package_id": "com.visualstudio.code",
  "project_dir": "CI_ll_com.visualstudio.code",
  "errors": [],
  "warnings": []
}
```

#### 0.2 修复 package_id

使用 `scripts/fix_package_id.sh` 修复 package_id 相关问题：

```bash
# 模拟执行（查看将要进行的修改）
./scripts/fix_package_id.sh CI_ll_com.visualstudio.code --dry-run

# 修复 linglong.yaml 中的 package.id
./scripts/fix_package_id.sh CI_ll_com.visualstudio.code --new-id com.visualstudio.code

# 修复并重命名工程目录
./scripts/fix_package_id.sh CI_ll_wrong.name --new-id com.visualstudio.code --rename-dir

# 详细输出
./scripts/fix_package_id.sh CI_ll_com.visualstudio.code --verbose
```

**修复项：**
- 更新 linglong.yaml 中的 `package.id`
- 更新 desktop 文件中的相关引用
- 重命名工程目录（需启用 `--rename-dir`）

**输出示例：**
```
========================================
玲珑包ID修复工具
========================================
工程目录: /path/to/CI_ll_com.visualstudio.code

目标 package_id: com.visualstudio.code

[成功] 已更新 linglong.yaml 中的 package.id 为: com.visualstudio.code
[成功] 已检查 desktop 文件: com.visualstudio.code.desktop

========================================
修复报告
========================================
状态: success
工程目录: /path/to/CI_ll_com.visualstudio.code

已应用的修复:
  ✓ yaml_package_id: com.visualstudio.code
  ✓ desktop_file: com.visualstudio.code.desktop

========================================
```

#### 0.3 package_id 格式规范

玲珑包ID必须符合以下规范：
- **格式**：反向域名格式（如 `com.example.app`）
- **字符**：小写字母、数字、下划线、点
- **结构**：至少包含两个点分隔的部分
- **长度**：最大255字符
- **示例**：
  - ✅ `com.visualstudio.code`
  - ✅ `org.deepin.music`
  - ✅ `cn.wps.wps-office`
  - ❌ `VisualStudio.Code`（包含大写）
  - ❌ `code`（缺少域名前缀）
  - ❌ `com..example`（连续的点）

### 1. linglong.yaml 修复

#### 1.1 缩进修复

```python
import yaml

def fix_yaml_indentation(yaml_path: str):
    """修复YAML缩进问题"""
    with open(yaml_path, 'r') as f:
        content = f.read()
    
    # description至少4空格缩进
    # build至少2空格缩进
    
    lines = content.split('\n')
    fixed_lines = []
    in_description = False
    in_build = False
    
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        
        if stripped.startswith('description:'):
            in_description = True
            fixed_lines.append(line)
        elif stripped.startswith('build:'):
            in_build = True
            fixed_lines.append(line)
        elif in_description and stripped and not stripped.startswith('-'):
            # 确保description内容至少4空格
            if len(line) - len(stripped) < 4:
                fixed_lines.append('    ' + stripped)
            else:
                fixed_lines.append(line)
        elif in_build and stripped:
            # 确保build内容至少2空格
            if len(line) - len(stripped) < 2:
                fixed_lines.append('  ' + stripped)
            else:
                fixed_lines.append(line)
        else:
            fixed_lines.append(line)
        
        # 检测块结束
        if stripped and not stripped.startswith(' ') and not stripped.startswith('\t'):
            if in_description and not stripped.startswith('description'):
                in_description = False
            if in_build and not stripped.startswith('build'):
                in_build = False
    
    with open(yaml_path, 'w') as f:
        f.write('\n'.join(fixed_lines))
```

#### 1.2 必需字段补全

```python
def fix_yaml_required_fields(yaml_path: str, package_info: dict):
    """补全必需字段"""
    with open(yaml_path, 'r') as f:
        data = yaml.safe_load(f)
    
    # 确保version存在
    if 'version' not in data:
        data['version'] = package_info.get('ll_version', '1.0.0.0')
    
    # 确保package字段完整
    if 'package' not in data:
        data['package'] = {}
    
    package_fields = {
        'id': package_info.get('package_id'),
        'name': package_info.get('app_name'),
        'version': package_info.get('ll_version'),
        'kind': 'app',
        'architecture': package_info.get('ll_architecture'),
        'description': package_info.get('description', '')
    }
    
    for key, value in package_fields.items():
        if key not in data['package'] and value:
            data['package'][key] = value
    
    # 确保base存在
    if 'base' not in data:
        data['base'] = package_info.get('base', 'org.deepin.base/23.1.0')
    
    # 确保command存在
    if 'command' not in data:
        data['command'] = [f"/opt/apps/{package_info['package_id']}/files/bin/{package_info['binary_name']}"]
    
    # 确保build存在
    if 'build' not in data:
        data['build'] = "cp -rf /project/binary/* ${prefix}/"
    
    with open(yaml_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
```

#### 1.3 command一致性修复

```python
def fix_yaml_command(yaml_path: str, desktop_exec: str):
    """修复command与desktop Exec一致"""
    # 从desktop Exec提取命令
    exec_cmd = desktop_exec.split()[0]  # 去除参数如 %U, %F
    
    with open(yaml_path, 'r') as f:
        data = yaml.safe_load(f)
    
    # 更新command
    data['command'] = [exec_cmd]
    
    with open(yaml_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)
```

### 2. desktop文件修复

#### 2.1 Icon路径修复

```python
def fix_desktop_icon(desktop_path: str):
    """修复Icon字段为相对路径"""
    with open(desktop_path, 'r') as f:
        lines = f.readlines()
    
    fixed_lines = []
    for line in lines:
        if line.startswith('Icon='):
            icon_path = line.split('=', 1)[1].strip()
            # 去除绝对路径前缀
            if icon_path.startswith('/'):
                # 提取图标名（不含扩展名）
                icon_name = Path(icon_path).stem
                line = f'Icon={icon_name}\n'
        fixed_lines.append(line)
    
    with open(desktop_path, 'w') as f:
        f.writelines(fixed_lines)
```

#### 2.2 Exec路径修复

```python
def fix_desktop_exec(desktop_path: str, package_id: str):
    """修复Exec字段"""
    with open(desktop_path, 'r') as f:
        lines = f.readlines()
    
    fixed_lines = []
    for line in lines:
        if line.startswith('Exec='):
            exec_value = line.split('=', 1)[1].strip()
            # 去除绝对路径
            parts = exec_value.split()
            cmd = parts[0]
            args = parts[1:] if len(parts) > 1 else []
            
            if cmd.startswith('/'):
                cmd = Path(cmd).name
            
            # 重建Exec行
            new_exec = 'Exec=' + cmd
            if args:
                new_exec += ' ' + ' '.join(args)
            line = new_exec + '\n'
        fixed_lines.append(line)
    
    with open(desktop_path, 'w') as f:
        f.writelines(fixed_lines)
```

#### 2.3 必需字段补全

```python
def fix_desktop_required_fields(desktop_path: str, package_info: dict):
    """补全desktop必需字段"""
    with open(desktop_path, 'r') as f:
        content = f.read()
    
    # 检查并添加必需字段
    required = {
        'Type': 'Application',
        'Name': package_info.get('app_name', ''),
        'Comment': package_info.get('description', ''),
        'Categories': 'Utility;'
    }
    
    for key, value in required.items():
        if f'{key}=' not in content and value:
            content += f'\n{key}={value}'
    
    with open(desktop_path, 'w') as f:
        f.write(content)
```

### 3. 图标目录结构修复

```python
def fix_icon_directory_structure(icons_dir: str):
    """修复图标目录结构"""
    icons_path = Path(icons_dir)
    
    # 标准尺寸
    standard_sizes = ['16x16', '22x22', '24x24', '32x32', '48x48', 
                      '64x64', '128x128', '256x256', '512x512', 'scalable']
    
    # 确保hicolor目录存在
    hicolor_dir = icons_path / 'hicolor'
    hicolor_dir.mkdir(parents=True, exist_ok=True)
    
    # 整理图标文件
    for icon_file in icons_path.rglob('*'):
        if icon_file.is_file() and icon_file.suffix in ['.png', '.svg', '.svgz', '.xpm']:
            # 确定目标目录
            if icon_file.suffix == '.svg':
                target_dir = hicolor_dir / 'scalable' / 'apps'
            else:
                # 根据文件名或尺寸确定目录
                size = detect_icon_size(icon_file)
                target_dir = hicolor_dir / size / 'apps'
            
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(icon_file), str(target_dir / icon_file.name))
```

### 4. 二进制文件修复

```python
def fix_binary_permissions(bin_dir: str):
    """修复二进制文件权限"""
    import stat
    
    bin_path = Path(bin_dir)
    
    for binary in bin_path.rglob('*'):
        if binary.is_file():
            # 检查是否为ELF文件
            try:
                with open(binary, 'rb') as f:
                    magic = f.read(4)
                    if magic == b'\x7fELF':
                        # 添加可执行权限
                        current_mode = binary.stat().st_mode
                        binary.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            except:
                pass
```

## 修复流程

```python
def fix_project(project_dir: str, validation_report: dict) -> dict:
    """执行完整修复流程"""
    fixes_applied = []
    
    # 1. 修复linglong.yaml
    if validation_report.get('yaml_validation', {}).get('status') == 'failed':
        yaml_path = f"{project_dir}/templates/linglong.yaml"
        fix_yaml_indentation(yaml_path)
        fix_yaml_required_fields(yaml_path, validation_report['package_info'])
        fixes_applied.append('yaml_indentation')
        fixes_applied.append('yaml_required_fields')
    
    # 2. 修复desktop文件
    if validation_report.get('structure_validation', {}).get('desktop_files', {}).get('status') == 'failed':
        desktop_dir = f"{project_dir}/templates/files_res/share/applications"
        for desktop in Path(desktop_dir).glob('*.desktop'):
            fix_desktop_icon(str(desktop))
            fix_desktop_exec(str(desktop), validation_report['package_info']['package_id'])
            fixes_applied.append(f'desktop_{desktop.name}')
    
    # 3. 修复图标目录
    if validation_report.get('structure_validation', {}).get('icons', {}).get('status') == 'failed':
        icons_dir = f"{project_dir}/templates/files_res/share/icons"
        fix_icon_directory_structure(icons_dir)
        fixes_applied.append('icon_structure')
    
    # 4. 修复二进制权限
    if validation_report.get('structure_validation', {}).get('binaries', {}).get('status') == 'failed':
        bin_dir = f"{project_dir}/templates/files_res/bin"
        fix_binary_permissions(bin_dir)
        fixes_applied.append('binary_permissions')
    
    return {
        'status': 'success',
        'fixes_applied': fixes_applied,
        'message': f'Applied {len(fixes_applied)} fixes'
    }
```

## 输出格式

```json
{
  "status": "success",
  "project_dir": "CI_ll_com.example.app",
  "fixes_applied": [
    "yaml_indentation",
    "yaml_required_fields",
    "desktop_com.example.app.desktop",
    "icon_structure"
  ],
  "details": {
    "yaml_indentation": {"before": "2 spaces", "after": "4 spaces"},
    "desktop_com.example.app.desktop": {"Icon": "/usr/share/icons/app.png -> app"}
  }
}
```

## 注意事项

1. 修复前备份原文件
2. 修复后重新运行验证确认问题已解决
3. 无法自动修复的问题记录并提示用户手动处理
4. 多次修复可能需要迭代执行
