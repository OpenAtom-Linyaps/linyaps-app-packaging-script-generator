# bin2linyaps.external-missing-deps-fetch.skill 设计文档
这个skill/agent主要用于更新已初始化的linglong.yaml, 用于为玲珑构建项目规则`linglong.yaml`更新补充上游源码信息，更新构建规则使其符合最新代码结构

这个skill主要用于分析linglong工程构建后在构建缓存目录中生成的`missing_deps.csv`或`missing_deps.json`, 从文件中提取缺失的so文件名，调用apt-file查找, 最终将依赖融合入项目
\* 需要开发者提前在环境配置好apt仓库并刷新apt-cache

## workflow
 - 上一流程开展打包测试后, 将工程项目所在路径传递到此, 需要上一流程执行pak_linyaps时禁用auto clean能力
 - 检查工程项目中是否存在`missing_deps.csv`或`missing_deps.json`, 这两个实际是内容一致的不同格式副本
 - 通过jq或其他性能更好的工具解析`missing_deps.csv`或`missing_deps.json`, 二选一, 遵循性能优先原则
 - 提取so文件名后, 使用sort或更优方案进行去重
 - 去重完成, 通过脚本调用`apt-file search`模糊匹配包含此文件的具体软件包名
 - 搜索得出软件包名, 分两步操作
  - 将软件包名追加写入该应用的模板linglong.yaml depend中
  - 通过`apt`获取软件包的完整下载地址, 即可以通过wget下载的url, 通过conf文件写入应用的构建工程目录模板中, 和linglong.yaml同级.提供独立脚本, 使pak_linyaps在执行打包时可以将这些deb下载下来并解压到binary_dir

## 参考文件
 - `examples/missing_deps.example.csv`: 某构建工程生成的so文件名清单
 - `examples/missing_deps.example.json`: 和`missing_deps.example.csv`内容一致, 仅格式改为json
 - `examples/linyaps-packager-skill-enhanced-master/linglong-pica-helper`: 参考L766函数localRepoDepsMatchAndFix, 有提及直接从apt仓库及拉取deb并管理的能力
 - `examples/debian-rules-to-linyaps-rules-master/skills/src2linyaps.debian.test-deps`: 参考依赖包dry-run安装测试的实现

## 输入
 - 应用打包工程模板目录, 一般是`CI_ll_xxx`
 - 某版本的英欧也能给打包工程临时文件, 由执行pak_linyaps打包的上一阶段引入

## 输出
 - 经过依赖补充之后的应用打包工程模板目录, 一般是`CI_ll_xxx`