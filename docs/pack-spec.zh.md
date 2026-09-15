# MenuMate 扩展包规范

[English](pack-spec.md) · 简体中文

一个扩展包是一个根目录含 `manifest.json` 的 Git 仓库。一个包可以声明多个动作，动作可分别启用，也可拥有独立的 HTML 弹窗；安装、更新和卸载以包为单位。

第一次写扩展包，先看[开发指南](extension-development.zh.md)和[入门包](../examples/selection-info-pack/)。本文用于查阅字段和协议细节。

## 目录与导入

```text
image-tools/
├── manifest.json
├── actions/
│   ├── compress.zsh
│   └── convert.zsh
└── ui/
    ├── compress.html
    ├── convert.html
    └── assets/
```

导入支持 `owner/repo`、完整 Git URL、本地 Git 仓库路径。仓库子目录不能独立安装，发布时应将包内容放在仓库根目录。

[普通脚本示例](../examples/example-pack/)展示直接执行和子菜单；[图片工具示例](../examples/image-tools-pack/)展示一个包内两个独立 HTML 动作。在主项目根目录运行 `zsh scripts/prepare-image-tools-pack.sh`，会生成可直接导入的本地 Git 仓库。

## 清单

```json
{
  "schemaVersion": 2,
  "name": "Image Tools",
  "author": "MenuMate",
  "description": "图片处理工具",
  "icon": "photo",
  "actions": [
    {
      "id": "compress-jpeg",
      "title": "图片压缩",
      "icon": "photo",
      "script": "actions/compress.zsh",
      "targets": "files",
      "utis": ["public.jpeg"],
      "placement": "topLevel",
      "timeoutSeconds": 60,
      "interface": { "entry": "ui/compress.html", "width": 500, "height": 600 }
    }
  ]
}
```

纯脚本包可以使用版本 1；省略版本仍按 1 解释。含 `interface` 的包必须显式声明版本 2，让旧客户端拒绝不支持的交互包。未知字段会被忽略。

| 字段 | 含义 |
| --- | --- |
| `name` / `actions` | 非空包名和动作数组，必填 |
| `author` / `description` / `icon` | 展示元信息；包图标默认为 `shippingbox` |
| 动作 `id` / `title` / `script` | 必填；ID 在包内唯一且应保持稳定，脚本为包内相对路径 |
| 动作 `targets` / `utis` | 默认 `any` / 不限制类型；类型按 UTI 从属关系匹配 |
| 动作 `placement` / `variants` | 默认菜单顶层、无子菜单；详见下文 |
| 动作 `timeoutSeconds` | 默认 60 秒；执行器允许 1–3600 秒 |
| 动作 `interface` | 可选本地 HTML 入口；省略即直接执行 |

脚本和 HTML 路径不得是绝对路径或含 `..` 路径段。导入会检查入口存在、可读取，以及符号链接解析后仍位于包内。HTML 入口必须为 `.html` 或 `.htm`，大小不超过 1 MiB。

动作 ID 是更新匹配依据；修改 ID 会被视为删除旧动作、增加新动作。标题可以调整，不能把标题当作稳定 ID。

## 多语言名称与说明

保留必填的 `name` 和动作 `title` 作为默认文本，再提供可选的语言字典：

```json
{
  "schemaVersion": 1,
  "name": "Image Tools",
  "localizedNames": {"en": "Image Tools", "zh-Hans": "图片工具"},
  "description": "Image utilities",
  "localizedDescriptions": {"en": "Image utilities", "zh-Hans": "图片处理工具"},
  "actions": [{
    "id": "convert", "title": "Convert image", "script": "convert.zsh",
    "localizedTitles": {"en": "Convert image", "zh-Hans": "图片转换"}
  }]
}
```

这些元信息字段支持 schema 1 和 2；旧客户端继续使用默认文本。优先匹配完整语言标记，再回退到语言或书写体系，例如 `en-US` 回退 `en`，`zh-CN` 回退 `zh-Hans`。未提供或为空的翻译使用默认名称，不会把繁体中文自动替换成简体。

App 将当前语言随快照传给 Finder。动作 ID、脚本路径和子菜单参数不随语言改变；固定子菜单值仍按作者原文显示。最近执行保存当时显示的名称，不会改写历史记录。

用户可在动作编辑器的“多语言名称”中修改英文和简体中文。包更新按语言合并，保留用户修改和主动清空的翻译；其他语言可通过清单或配置 JSON 提供。HTML 页面仍由作者根据 `locale` 自行翻译。

## 匹配与子菜单

| `targets` | 何时出现 |
| --- | --- |
| `files` | 选中文件；App 等文件包按文件处理 |
| `folders` | 选中文件夹 |
| `any` | 选中文件、文件夹或二者混合 |
| `container` | 文件夹空白处；不是选中文件夹本身 |

每个选中项都必须符合动作的目标及至少一个允许类型。`utis` 留空表示不限制；例如 `public.image` 匹配其图片子类型。符号链接按目标元数据匹配，但脚本仍收到选中的链接路径。

`placement` 为 `topLevel` 或 `submenu`。`variants` 决定动作是否展开子菜单：

```json
{"variants": {"fixed": ["png", "jpeg", "tiff"]}}
```

```json
{"variants": {"directoryListing": "Templates"}}
```

目录相对 MenuMate 配置目录解析，也可在现有动作配置中使用绝对路径。目录子菜单排除隐藏文件和子目录，最多列出 50 项。选中的文件名或固定值通过 `MENUMATE_VARIANT` 传给脚本；没有 `variants` 时传空值。

## 脚本环境契约

动作通过 `/bin/zsh` 执行，脚本不需要可执行位。

| 参数 / 变量 | 含义 |
| --- | --- |
| `$1 … $n` | 所选项绝对路径；空白处动作传容器路径 |
| `MENUMATE_PATHS` | 换行拼接的路径；处理任意文件名时应优先使用 `"$@"` |
| `MENUMATE_VARIANT` | 子菜单值，没有则为空 |
| `MENUMATE_INPUT` | HTML 提交的 JSON 对象；普通执行默认 `{}` |
| `MENUMATE_LOCALE` | App 当前语言，例如 `en`、`zh-Hans` |
| `MENUMATE_DATA` / `MENUMATE_TEMPLATES` | 数据、模板目录 |
| `MENUMATE_TERMINAL` / `MENUMATE_EDITOR` | 用户选择的终端、编辑器 bundle ID；未设置时可能不存在 |
| `MENUMATE_SCRIPT` | 文件脚本的绝对路径；可用 `${0:A:h}` 定位脚本旁的资源 |
| 工作目录 | 根据首个选中项计算；目录本身或文件所在目录 |
| 退出码 | `0` 为成功，非零为失败；stdout 首行作为摘要，错误可进入历史和通知 |

不要将路径或 JSON 参数拼接为命令执行。解析字段后校验允许值，并使用带引号的参数数组调用工具。

## HTML 窗口

页面通过原生 WKWebView 承载，远程页面、资源及跳转由宿主限制。将依赖资源放在 HTML 入口所在目录或其子目录，宿主的文件读取范围限定在入口目录内。页面标题、按钮和说明的翻译由包作者提供。

加载时宿主提供：

```js
const {runID, title, files, variant, locale, parameters, isTestRun, testRoot}
  = window.menumate.context;
// files: [{name, path}]
// parameters: 上次明确选择记住的参数，首次为空对象
```

在用户点击页面按钮后提交：

```js
window.menumate.submit({quality: 80, maxEdge: 1920, output: "same"}, true);
// 第二个参数表示记住本次选项；试运行不会保存此偏好。
```

参数根节点必须是 JSON 对象，编码后不超过 64 KiB。宿主将它放入 `MENUMATE_INPUT`，不会将它插入 shell 命令。一个窗口只能提交一次，也不能请求执行另一个动作。取消使用 `window.menumate.cancel()`；脚本运行期间不接受关闭请求。

接收结果：

```js
window.addEventListener("menumate:result", ({detail}) => {
  const {exitCode, stdout, stderr, timedOut} = detail;
  // 将结果渲染到页面；使用 textContent 展示输出。
});
```

普通执行可记住参数；取消不保存，试运行也不保存。页面和脚本都属于需要审查的运行代码，查看过源码不代表自动获得安全保证。

## 导入与更新审查

导入先克隆，不执行动作脚本；用户查看声明的脚本及 HTML，并确认额外文件提示后，才会安装。全部动作默认关闭，之后可分别启用。重复导入已安装包会提示通过“检查更新”操作。

更新比较远端默认分支与已安装提交，重新克隆并显示包内变化，排除仓库根 `.git` 元数据。审查范围包含清单、JS/CSS、隐藏文件、权限和符号链接目标。二进制及超过 256 KiB 的文本显示大小和完整内容的 SHA-256 摘要。无法读取的文件会阻止更新审查；每个目录树最多 10,000 个条目、32 MiB 预览数据。

更新保留已有动作的开关与排序；标题和菜单位置若与旧清单默认值不同，则保留用户改动，否则采用新版默认值。新增动作默认关闭，远端删除的动作会移除。导入、更新、卸载会记录事务并备份旧包；包目录、installed.json 和 config.json 在失败或 App 中断后恢复一致状态。启动时先恢复未完成事务，再提供动作。打开的 HTML 弹窗及排队、执行中的动作会阻止更新与卸载。恢复记录或备份损坏时保留现场并提示错误，不会猜测后继续安装。

## 临时样本试运行

试运行创建 `~/Library/Application Support/MenuMate/TestRuns/<UUID>/`，内部有 Inputs、Data、Templates、Temporary，自动填充适配规则的资源。输出保留供查看。脚本额外收到 `MENUMATE_TEST_RUN=1`、`MENUMATE_TEST_ROOT` 和临时 `TMPDIR`。

标准 Templates 子菜单提供生成模板；自定义目录不能模拟时明确报错，不会复制真实用户文件，也不会换成无关模板。最多生成 20 个选中样本；不支持的类型和不满足的数量范围会失败。

临时目录不是进程沙箱。脚本仍拥有用户权限，硬编码路径、剪贴板和应用自动化可能影响真实环境。试运行使用配置的实际脚本，不会重写其任意文件访问。

## 发布与发现

把符合规范的包作为独立 Git 仓库发布；添加 GitHub topic `menumate-pack` 可用于社区发现。本地 HTML 示例脚本可作为起点，建议减少运行依赖、保留原文件，并说明格式或平台限制。
