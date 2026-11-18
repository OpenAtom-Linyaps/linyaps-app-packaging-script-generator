# files_res 目录结构参考

## 目录结构

```
templates/files_res/
└── share/
    ├── applications/           # Desktop Entry 文件 (.desktop)
    ├── icons/
    │   └── hicolor/            # 仅允许 hicolor 主题
    │       └── <size>/
    │           └── <category>/
    ├── mime/
    │   └── packages/           # MIME 类型定义文件 (.xml)
    └── pixmaps/                # 不使用（仅作 fallback，建议不提供）
```

## 1. Desktop 文件规范

遵循 [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)。

### 文件位置与命名

- 位置：`share/applications/<app-id>.desktop`
- 后缀：`.desktop`
- 编码：UTF-8

### 必填字段

| 字段 | 说明 | 示例 |
|------|------|------|
| `Type` | 应用类型，固定为 `Application` | `Application` |
| `Name` | 应用显示名称 | `My App` |
| `Exec` | 启动命令（见下方语法规则） | `/opt/apps/com.example.app/files/bin/app %F` |
| `Icon` | 图标名称（不带路径和后缀） | `com.example.app` |
| `Categories` | 应用分类（见下方注册规则） | `Development;IDE;` |

### Exec 参数语法

| 参数 | 含义 | 使用场景 |
|------|------|---------|
| `%f` | 单个文件名 | 单文件打开 |
| `%F` | 多个文件名 | 多文件打开 |
| `%u` | 单个 URL | 单 URL 打开 |
| `%U` | 多个 URL | 多 URL 打开 |
| `%%` | 百分号转义 | 字面量 `%` |

### Categories 注册规则

- 必须使用 [Registered Categories](https://standards.freedesktop.org/desktop-entry-spec/latest/apa.html)
- 多个类别用 `;` 分隔，结尾必须有 `;`
- 常见类别：`Development`、`IDE`、`TextEditor`、`Utility`、`Graphics`、`Network`、`Office`、`AudioVideo`、`Game`

### 字段合并

跨目录去重时，`dedup_desktop_files.sh` 删除 binary/ 重复 desktop 前会先将 binary/ 中 files_res/ **缺失**的字段合并到 files_res/ 文件：

- **files_res/ 已有的字段值保留不变**（模板权威），仅追加缺失的 key
- 合并本地化字段：`Name[locale]`、`Comment[locale]`、`GenericName[locale]`、`Keywords[locale]`（每个语言一个 key，不冲突）
- 合并非本地化字段：`Comment`、`GenericName`、`Categories`、`MimeType`、`Keywords`、`Terminal`、`StartupNotify`、`StartupWMClass`、`Encoding`（仅当 files_res/ 缺失时补充）
- `[Desktop Action xxx]` 段：files_res/ 缺少的整段追加；已有段内逐字段比较补充缺失 key
- 不合并：`Exec`（pak_linyaps.sh 统一重写）、`NoDisplay`（分组用）、`Path`、`Type`、`Icon`、`Name`（无 locale）

### 示例

```desktop
[Desktop Entry]
Name=My Application
Comment=Description of my application
GenericName=Text Editor
Exec=/opt/apps/com.example.app/files/bin/app %F
Icon=com.example.app
Type=Application
StartupWMClass=myapp
Categories=Development;TextEditor;IDE;
MimeType=text/plain;inode/directory;
Keywords=keyword1;keyword2;

Terminal=false
StartupNotify=true

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/opt/apps/com.example.app/files/bin/app --new-window %F
Icon=com.example.app
```

## 2. 图标规范

遵循 [Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/)。

### 核心约束

- **只允许使用 `hicolor` 主题**，禁止使用 `gnome`、`adwaita`、`breeze` 等其他主题目录
- `share/pixmaps/` 不应使用（仅作为极低优先级的 fallback，建议不提供）

### 目录结构

```
share/icons/hicolor/<size>/<category>/
```

### 标准尺寸

| 尺寸 | 说明 |
|------|------|
| `16x16` | 菜单、工具栏小图标 |
| `24x24` | 面板图标 |
| `32x32` | 按钮、列表图标 |
| `48x48` | 文件管理器图标 |
| `64x64` | 应用程序图标 |
| `128x128` | 应用程序图标（高分辨率） |
| `256x256` | 应用程序图标（高分辨率） |
| `512x512` | 应用程序图标（推荐） |

至少提供 `512x512` 或 `256x256` 尺寸。

### Category 类别

| 类别 | 说明 |
|------|------|
| `apps` | 应用程序图标 |
| `actions` | 动作图标（保存、删除等） |
| `devices` | 设备图标（打印机、硬盘等） |
| `mimetypes` | MIME 类型图标 |
| `places` | 位置图标（文件夹、桌面等） |
| `status` | 状态图标（警告、错误等） |

### 命名规则

- 推荐使用反向域名格式：`com.example.app.png`
- 也可使用通用名称：`app.png`
- 文件格式：PNG（推荐）或 SVG

### 示例

```
share/icons/hicolor/512x512/apps/com.example.app.png
share/icons/hicolor/256x256/apps/com.example.app.png
share/icons/hicolor/48x48/apps/com.example.app.png
```

## 3. MIME 类型规范

遵循 [Shared MIME Info Specification](https://specifications.freedesktop.org/shared-mime-info-spec/latest/)。

### 文件位置

- 位置：`share/mime/packages/<app-id>.xml`
- 编码：UTF-8

### XML 格式要求

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
    <mime-type type="application/x-app-workspace">
        <comment>Application Workspace</comment>
        <glob pattern="*.app-workspace"/>
    </mime-type>
</mime-info>
```

### 关键元素

| 元素 | 说明 | 示例 |
|------|------|------|
| `<mime-type>` | MIME 类型定义，`type` 属性为完整 MIME 类型 | `application/x-app-workspace` |
| `<comment>` | 可读描述 | `Application Workspace` |
| `<glob>` | 文件扩展名匹配，`pattern` 属性为 glob 模式 | `*.app-workspace` |
| `<magic>` | 文件魔数匹配（可选） | 文件头字节序列 |

### glob 匹配规则

- `*.ext` — 匹配所有以 `.ext` 结尾的文件
- `pattern` 中的 `*` 匹配任意字符序列
- 多个 `<glob>` 元素可定义多个扩展名

## 4. 注意事项

- `files_res/` 目录下的文件直接映射到玲珑容器内的 `$prefix/`（即 `/usr/`）
- `files_res/share/applications/` 对应 `/usr/share/applications/`
- `files_res/share/icons/` 对应 `/usr/share/icons/`
- `files_res/share/mime/` 对应 `/usr/share/mime/`
- desktop 文件中的 `Exec` 路径使用的是玲珑容器内的路径，而非宿主机的路径
- 图标名的 `.png` 后缀不应出现在 desktop 文件的 `Icon=` 字段中