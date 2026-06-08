# appimage-linyaps 设计文档

## 项目概述

### 目标
设计并实现 `appimage-linyaps` 技能，用于将 AppImage 应用程序转换为玲珑（Linyaps）包格式。该技能基于现有的 `tar-linyaps` 技能架构，但专门针对 AppImage 的特性进行优化。

### 核心价值
1. **AppImage 专用处理**：专门处理 AppImage 的解压、元数据提取和 Exec 命令解析
2. **Wrapper 机制**：采用 Go 版本 ll-pica 的 wrapper 方式，保留 AppImage 原始目录结构
3. **智能 Exec 提取**：从 desktop 文件中准确提取 Exec 命令，支持多种 AppImage 变体
4. **版本号自动提取**：从文件名中智能提取版本号，支持多种版本号格式

## 业务流程设计

### 阶段 1：输入验证和准备
1. **接收输入**：
   - AppImage 文件路径（本地文件或 URL）
   - 用户提供的配置参数（app_name, package_id, description 等）
   - 可选的显式 Exec 命令覆盖

2. **输入验证**：
   - 验证 AppImage 文件存在且格式正确
   - 验证必填参数完整性
   - 验证 package_id 格式（反向域名格式）

### 阶段 2：AppImage 解压和元数据提取
1. **解压 AppImage**：
   - 使用 `chmod +x` + `--appimage-extract` 解压
   - 生成 `squashfs-root/` 目录
   - 验证解压结果和 AppRun 存在性

2. **提取元数据**：
   - 从 desktop 文件提取：app_name, description, icon_name
   - 从文件名提取：version（多模式正则）
   - 从 desktop 文件名推导：package_id（反向域名格式）

3. **解析 Exec 命令**：
   - 优先使用用户显式指定的 `binary_name`
   - 如果未指定，使用 `resolve_exec_command.sh` 从 desktop 文件提取
   - 支持多种 Exec 模式：AppRun, AppRun.wrapped, 直接二进制, ${HERE} 变量

### 阶段 3：构建目录初始化
1. **创建目录结构**：
   ```
   build_dir/
   ├── binary/          # 对应 $prefix/ (files/)
   │   └── lib/
   │       └── ${APP_PREFIX}/
   │           └── squashfs-root/  # 保留原始结构
   ├── files_res/       # 资源文件（desktop, icon）
   └── linglong.yaml    # 玲珑包配置
   ```

2. **复制 AppImage 内容**：
   - 将 `squashfs-root/` 完整复制到 `binary/lib/${APP_PREFIX}/`
   - 保持原始目录结构不变
   - **不修改**任何内部路径

3. **生成 Wrapper 脚本**：
   - 在 `binary/` 根目录创建 wrapper 脚本
   - Wrapper 内容：`cd lib/${APP_PREFIX} && ./AppRun $@`
   - 设置 wrapper 脚本可执行权限

### 阶段 4：资源文件处理
1. **Desktop 文件处理**：
   - 从 `squashfs-root/` 复制 desktop 文件到 `files_res/`
   - **不修改** Exec 字段（由 wrapper 自动处理）
   - 修复 Icon 路径为相对路径

2. **图标文件处理**：
   - 从 `squashfs-root/` 复制图标文件到 `files_res/`
   - 支持多种图标格式（png, svg, xpm）
   - 处理图标路径引用

3. **去重处理**：
   - 使用 `dedup_desktop_files.sh` 去重 desktop 文件
   - 避免重复的 desktop 条目

### 阶段 5：玲珑包配置生成
1. **生成 linglong.yaml**：
   - 使用模板填充变量
   - 设置 base 和 runtime 层
   - 配置构建命令

2. **版本号处理**：
   - 确保版本号为 `X.Y.Z.W` 格式
   - 处理版本号不足 4 位的情况
   - 验证版本号格式

3. **架构配置**：
   - 设置目标架构（x86_64, arm64 等）
   - 验证架构兼容性

### 阶段 6：构建和打包
1. **执行 ll-builder build**：
   - 使用生成的 linglong.yaml 进行构建
   - 处理构建错误和警告
   - 验证构建结果

2. **导出 layer 文件**：
   - 使用 ll-builder export 生成 .layer 文件
   - 设置输出目录和文件名
   - 验证导出结果

3. **可选推送**：
   - 推送到开发仓库（如果配置）
   - 处理推送错误
   - 验证推送结果

### 阶段 7：清理和输出
1. **清理临时文件**：
   - 删除构建临时目录
   - 清理解压的 AppImage 文件
   - 保留最终输出文件

2. **输出结果**：
   - 显示构建成功信息
   - 输出 .layer 文件路径
   - 提供后续操作建议

## 关键设计决策

### 1. Wrapper 机制 vs 路径扁平化

**选择**：Wrapper 机制（保留原始结构）

**理由**：
- AppImage 解压后可能包含复杂的相对路径关系
- 修改路径可能导致应用程序无法正常运行
- Wrapper 方式更安全，保持 AppImage 原有执行逻辑
- Go 版本 ll-pica 验证了此方案的可行性

**实现**：
```bash
# Wrapper 脚本内容
#!/bin/bash
cd "$(dirname "$0")/lib/${APP_PREFIX}"
exec ./AppRun "$@"
```

### 2. Exec 命令处理策略

**策略**：智能提取 + 显式覆盖

**流程**：
1. 优先使用用户通过 `--binary_name` 显式指定的命令
2. 如果未指定，使用 `resolve_exec_command.sh` 从 desktop 文件提取
3. 提取失败时，使用 `scan_executables.sh` 扫描可执行文件作为备用

**关键约束**：
- **不修改** desktop 文件的 Exec 字段
- **不手动设置** linglong.yaml 的 command 字段
- **让** pak_linyaps.sh 通过 wrapper 机制自动处理

### 3. 版本号处理策略

**策略**：多模式正则提取 + 格式标准化

**支持格式**：
- `-v1.2.3` 或 `-V1.2.3`
- `-1.2.3-` 或 `_1.2.3_`
- `1.2.3` 在文件名开头
- 任何位置的 `1.2.3.4` 格式

**标准化**：确保版本号为 `X.Y.Z.W` 格式（ll-builder 要求）

### 4. 目录结构设计原则

**原则**：
- `binary/` 对应 `$prefix/`（files/）
- `squashfs-root` 保持原始结构，安装到 `lib/${APP_PREFIX}/`
- `files_res/` 存放 desktop 文件、图标等资源
- **不修改** AppImage 内部路径结构

## 脚本架构设计

### 1. 核心脚本（已实现）

#### `extract_appimage.sh`
- **职责**：解压 AppImage 文件
- **输入**：AppImage 文件路径，输出目录
- **输出**：squashfs-root 目录
- **验证**：ELF 格式，AppRun 存在性

#### `resolve_exec_command.sh`
- **职责**：从 desktop 文件提取 Exec 命令
- **输入**：squashfs-root 目录
- **输出**：解析后的 binary name
- **支持模式**：AppRun, AppRun.wrapped, 直接二进制, ${HERE} 变量

#### `parse_appimage_metadata.sh`
- **职责**：提取 AppImage 元数据
- **输入**：AppImage 文件，squashfs-root 目录
- **输出**：key=value 格式的元数据
- **提取内容**：app_name, package_id, description, binary_name, icon_name, version

#### `parse_build_config.sh`
- **职责**：解析构建配置 JSON
- **输入**：配置文件路径
- **输出**：扁平化的 key=value 格式
- **验证**：必填字段，可选字段默认值

### 2. 主构建脚本（待实现）

#### `pak_linyaps.sh`
- **职责**：主构建编排脚本
- **核心逻辑**：
  1. 初始化全局数据（参数解析、验证）
  2. 解压 AppImage（使用 extract_appimage.sh）
  3. 提取元数据（使用 parse_appimage_metadata.sh）
  4. 解析 Exec 命令（使用 resolve_exec_command.sh）
  5. 构建目录初始化（wrapper 机制）
  6. 生成 desktop 文件和图标
  7. 执行 ll-builder build 和 export
  8. 推送到开发仓库（可选）

### 3. 辅助脚本（待复制）

#### `dedup_desktop_files.sh`
- **职责**：去重 desktop 文件
- **来源**：tar-linyaps 技能

#### `validate_bin_nesting.sh`
- **职责**：验证二进制嵌套
- **来源**：tar-linyaps 技能

#### `scan_executables.sh`
- **职责**：扫描可执行文件（备用）
- **来源**：tar-linyaps 技能

## 配置文件设计

### 1. 构建配置 JSON

```json
{
  "main": {
    "src_url": "/path/to/application.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "A sample application converted from AppImage",
    "binary_name": "",
    "icon_url": ""
  },
  "optional": {
    "app_version": "",
    "base_id": "org.deepin.base",
    "base_version": "25.2.2",
    "runtime_id": "org.deepin.runtime.dtk",
    "runtime_version": "25.2.2",
    "linyaps_arch": "x86_64",
    "output_dir": "./output"
  }
}
```

### 2. 玲珑包模板

```yaml
version: "1.0"

package:
  id: ${package_id}
  name: "${app_name}"
  version: ${ll_version}
  kind: app
  architecture: ${ll_architecture}
  description: |
    ${description}

base: ""
runtime: ""

command: ""

build: |
  ## Extract AppImage res
  # binary/ 的内容直接对应 $prefix/ (files/)
  # AppImage 的 squashfs-root 保持原始結構，安裝到 lib/${APP_PREFIX}/
  cp -rf /project/binary/* ${prefix}/

  # 複製桌面文件、圖標等資源
  cp -rf /project/files_res/* ${prefix}/

  # Add an identity for LLM
  touch ${prefix}/.linyaps_genius
```

## 测试策略

### 1. 单元测试
- 测试每个脚本的独立功能
- 验证参数解析、错误处理
- 测试边界条件

### 2. 集成测试
- 测试脚本间的协作
- 验证数据流转
- 测试配置解析和验证

### 3. 端到端测试
- 测试完整的转换流程
- 使用真实的 AppImage 文件
- 验证生成的玲珑包

## 错误处理策略

### 1. 输入验证错误
- 清晰的错误信息
- 指出具体的错误参数
- 提供修正建议

### 2. 文件操作错误
- 文件不存在
- 权限不足
- 磁盘空间不足

### 3. 构建过程错误
- 依赖缺失
- 编译失败
- 链接错误

### 4. 网络错误
- URL 下载失败
- 网络超时
- 证书错误

## 性能优化

### 1. 文件操作优化
- 避免不必要的文件复制
- 使用硬链接或符号链接
- 减少磁盘空间使用

### 2. 构建过程优化
- 并行处理
- 增量构建
- 缓存机制

### 3. 网络优化
- 并行下载
- 断点续传
- 压缩传输

## 安全考虑

### 1. 文件验证
- 验证 AppImage 文件格式
- 检查文件完整性
- 防止恶意文件

### 2. 路径安全
- 防止路径遍历攻击
- 验证文件路径合法性
- 限制文件访问范围

### 3. 权限控制
- 最小权限原则
- 临时文件权限
- 输出文件权限

## 后续优化方向

### 1. 功能增强
- 支持 AppImage 更新检测
- 添加依赖关系分析
- 支持多架构构建
- 支持 AppImage 签名验证

### 2. 用户体验
- 图形界面支持
- 进度显示
- 交互式配置
- 详细的错误提示

### 3. 生态集成
- 与 CI/CD 集成
- 支持批量转换
- 插件系统支持
- 社区贡献机制

## 总结

`appimage-linyaps` 技能的设计遵循了以下原则：

1. **模块化**：每个脚本负责单一职责，便于维护和测试
2. **可扩展**：易于添加新功能和支持新的 AppImage 变体
3. **可靠性**：完善的错误处理和验证机制
4. **用户友好**：清晰的配置和详细的文档
5. **安全性**：严格的输入验证和权限控制

通过实现该技能，用户可以轻松地将 AppImage 应用程序转换为玲珑包格式，享受更好的应用分发和管理体验。该技能将成为玲珑生态系统中的重要工具，促进开源应用的传播和使用。