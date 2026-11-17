# linyaps-rules-upstream-update设计
这个skill/agent主要用于更新已初始化的linglong.yaml, 用于为玲珑构建项目规则`linglong.yaml`更新补充上游源码信息，更新构建规则使其符合最新代码结构

## 参考文件
 - `examples/linglong.kate.ai.yaml`: 初始化的构建规则，缺乏源码信息，构建规则不可直接使用
 - `examples/linglong.kate.ai.patched.yaml`: 补充了上游源码信息、更新了构建规则的yaml, 主要是追加了进入源码解压后路径的操作
 - `docs/manifests-for-yaml.md`: linglong.yaml配置文件规范和可用值声明, 主要参考支持的源码类型和格式
 - `examples/validate-linglong-yaml.py`: linglong.yaml格式化检测脚本

## 输入(多选一)
 - 项目源码url地址
 - 项目源代码git地址

## 产出
 - 更新后的项目构建规则文件linglong.yaml

## workflow
输入已适配项目路径/目录 >> 由用户输入上游更新信息 >> 根据源码类型下载文件到本地计算sha256 >> 解压源码提取源码解压结构 >> 更新linglong.yaml

## 约束
 - 传入的原始项目对应的linglong.yaml必须每一个字段都有内容且格式正确，可以通过脚本检测
 - build字段中必须包含操作`touch ${PREFIX}/.linyaps_genius`和`chmod -R 755 ${PREFIX}`
 - 正式构建规则中, 所有目录路径必须为${PREFIX}
 - 正式构建规则中, 第一个步骤必须为进入源码目录, 路径固定在`/project/linglong/sources`下的子目录，子目录命名参考`docs/manifests-for-yaml.md`