# linyaps-app-packaging-script-generator 新人必看
这是一个开箱即用的agent, 目前已支持通过deb、含二进制的tar压缩包转换为玲珑应用. 你在安装`Release`页面专用`linglong-bin`和`linglong-builder`后即可根据此文档开始使用

## 需要安装的依赖包
```bash
python3-yaml python3-ruamel.yaml
linglong-bin=1.13.7-ziggy2 linglong-builder=1.13.7-ziggy2
```

## 建议提示词
 - 帮我把本地目录`/path/to/your/file`安装包转换为玲珑应用
 - `https://linux.apps.demo.com/download/demo.deb`是一个Linux应用，帮我转换为玲珑应用

## skills能力介绍
 - `appimage-linyaps`: 用于将 AppImage 应用程序转换为玲珑（Linyaps）包格式。该技能基于 `tar-linyaps` 技能架构，专门针对 AppImage 的特性进行优化。
 - `tar-linyaps`: 將 Linux binary release tar 归档包转换成玲珑（Linyaps）應用便捷打包腳本。
 - `compat-testing`: 执行玲珑打包构建测试，验证生成的工程是否可以正常构建，并运行兼容性检测确保应用能在玲珑环境中正常运行。
 - `deb-analysis`: 解析Debian软件包(.deb)文件，提取元数据信息并解压文件内容，为后续玲珑打包工程生成提供基础数据。
 - `linglong-fix`: 根据验证报告自动修复玲珑构建项目中的问题，包括linglong.yaml格式、desktop文件、图标目录结构、二进制文件权限等。
 - `linglong-project-gen`: 根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 `linglong.yaml` 配置文件和 `pak_linyaps.sh` 打包脚本。
 - `project-structure-validator`: 验证玲珑打包项目目录结构和必要文件的完整性，确保项目符合打包要求。
 - `resource-collector`: 从deb包解压后的目录中提取应用资源文件（desktop文件、图标、appdata、补全脚本等），按照玲珑打包规范整理到 `files_res/` 目录结构中。



## 工作流程
1. 使用者切换agent至`linyaps-app-packaging-script-generator`
2. 使用者通过json任务列表等方式注入需要生成玲珑应用打包脚本的提示词
3. 等待初始化完成
4. 玲珑应用打包脚本初始化完成，可以根据参数说明执行应用打包工程的`pak_linyaps.sh`来进行打包

## 输出资源
支持手动修改、重复使用的应用打包脚本工程`CI_${ll_id}`, `${ll_id}`是实际项目对应的应用包名

```bash
CI_ll_app.netlify.ytdn
├── config
│   └── base_runtime_whitelist.conf
├── pak_linyaps.sh
├── reports
│   ├── structure_validation.json
│   └── yaml_validation.json
├── scripts
│   ├── dedup_desktop_files.sh
│   ├── handle_special_paths.sh
│   └── validate_bin_nesting.sh
└── templates
    ├── files_res
    │   └── share
    └── linglong.yaml
```

## 打包工程使用示例
```bash
./pak_linyaps.sh \
  --linyaps_arch=x86_64 \
  --origin_version="3.6.5" \
  --src_path="/media/deepin/Data/top100-CI/260602-init/src/siyuan-3.6.5-linux.deb" \
  --output_dir="/media/deepin/Data/top100-CI/260602-init/output" \
  --build_tmp_dir="/home/deepin/.cache/siyuan"
```

### 参数解释
 - --linyaps_arch: 玲珑构建工程架构，架构定义参考`x86_64` `arm64` `loong64`
 - --origin_version: 源码上游版本
 - --src_path: 源码本地绝对路径
 - --output_dir: layer包输出地址
 - --build_tmp_dir: 构建工程临时目录
\* 部分LLM生成脚本时可能会自行去除参数，使用参数前需要先确认当前`pak_linyaps`支持你导入的参数