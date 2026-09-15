# MenuMate 扩展包开发指南

[English](extension-development.md) · 简体中文 · [返回 README](../README.zh.md)

扩展包就是一个含 `manifest.json` 的 Git 仓库，里面可以有多个右键动作。每个动作对应一个 zsh 脚本；需要用户选择参数时，再为动作配置本地 HTML 弹窗。不需要修改或重新编译 MenuMate。

从[可直接复制的入门包](../examples/selection-info-pack/)开始。它有两个动作：“列出文件名”直接运行脚本；“所选文件信息”先弹窗选择文件名或完整路径，再展示结果。两个动作都不修改文件。

快速查阅：[开始运行](#从示例开始) · [动作清单](#定义动作与匹配条件) · [HTML 交互](#给动作加-html-弹窗) · [脚本参数](#脚本读取-html-参数) · [调试发布](#调试与发布)

## 从示例开始

以下终端命令从 **MenuMate 源码仓库根目录**执行，需要 macOS 和 Git。

1. 复制示例，创建独立 Git 仓库：

   ```sh
   pack_dir=$(mktemp -d "${TMPDIR:-/tmp}/menumate-starter.XXXXXX")
   cp -R examples/selection-info-pack/. "$pack_dir/"
   git -C "$pack_dir" init
   git -C "$pack_dir" add .
   git -C "$pack_dir" commit -m "Create MenuMate extension pack"
   printf '%s\n' "$pack_dir"
   ```

   如果 Git 提示缺少作者身份，在这个新仓库配置自己的 `user.name` 和 `user.email`，然后重新提交。把命令输出的目录路径复制下来。

2. 在 MenuMate **扩展包 → 导入扩展包**粘贴该路径，查看源码并确认安装。导入的是已提交内容的克隆；原仓库中未提交的修改不会进入安装副本。
3. 在“右键菜单”中搜索“所选文件信息”，点击**试运行**，选择支持的文件样本并运行。HTML 弹窗中选择“完整路径”，点击“运行”，应显示样本路径。动作尚未启用时也可试运行。
4. 在“扩展包”中启用需要的动作，再到 Finder 选中文件并右键。直接运行“列出文件名”的输出可在菜单栏**最近执行**查看；HTML 动作的输出会显示在弹窗内。
5. 修改原仓库文件后，执行 `git add`、`git commit`，再在 MenuMate 检查更新、查看差异并应用。不要直接修改安装副本，也不要通过重复导入更新同一个包。这个示例路径位于临时目录，长期开发请将仓库放到自己的项目目录。

目录结构如下：

```text
selection-info-pack/
├── manifest.json
├── actions/
│   ├── names.zsh       # 直接运行
│   └── report.zsh      # 读取 HTML 提交的参数
└── ui/
    └── report.html     # 选择参数、显示结果
```

## 定义动作与匹配条件

一个只列出文件名的包可以从这个清单开始：

```json
{
  "schemaVersion": 1,
  "name": "My File Tools",
  "actions": [{
    "id": "list-names",
    "title": "列出文件名",
    "icon": "list.bullet",
    "script": "actions/names.zsh",
    "targets": "files",
    "placement": "topLevel",
    "timeoutSeconds": 30
  }]
}
```

`actions/names.zsh`：

```zsh
#!/bin/zsh
emulate -L zsh
set -euo pipefail
for item in "$@"; do
  print -r -- "${item:t}"
done
```

宿主用 `/bin/zsh` 执行文件，无须 `chmod +x`。所选路径作为独立参数传入，用 `"$@"` 遍历；`${item:t}` 是 zsh 的文件名提取语法。不要把路径拼成字符串后交给 `eval`。

| 需求 | 配置方式 |
| --- | --- |
| 仅文件、仅文件夹、两者均可 | `targets` 分别设为 `files`、`folders`、`any` |
| 文件夹空白处的右键菜单 | `targets: "container"`；脚本收到容器目录路径 |
| 只处理图片或 JPEG | `utis: ["public.image"]` 或 `["public.jpeg"]`；每个选中项都须匹配 |
| 放进 MenuMate 分组 | `placement: "submenu"`；顶层用 `topLevel` |
| 动作下再展开格式等选项 | `variants: {"fixed": ["png", "jpeg"]}`；选中值通过 `MENUMATE_VARIANT` 传入 |

`placement` 决定动作放在哪里，`variants` 决定动作自身是否有子项。保持动作 `id` 稳定；改标题不会改变身份，改 ID 会被视为删除旧动作、添加新动作。脚本及 HTML 的入口路径相对包根目录，不能使用绝对路径或 `..`。

完整字段、默认值和目录型子菜单见[扩展包规范](pack-spec.zh.md)。

## 给动作加 HTML 弹窗

将清单的 `schemaVersion` 设为 **2**，在需要弹窗的动作上加 `interface`，同时保留 `script`：

```json
{
  "id": "selection-report",
  "title": "所选文件信息",
  "script": "actions/report.zsh",
  "targets": "files",
  "interface": {"entry": "ui/report.html", "width": 500, "height": 480}
}
```

同一个 schema 2 包内可以同时包含直接执行和 HTML 动作。不支持用远程网页 URL 作为入口。入口文件须为 `.html` 或 `.htm`，不超过 1 MiB；窗口宽度会限制到 360–900、高度到 320–900。

一次交互按以下顺序完成：

```text
Finder 点击动作 → 打开 HTML 并注入所选文件 → 用户填写选项
→ submit(JSON) → zsh 从 MENUMATE_INPUT 读取参数 → 结果事件返回 HTML
```

HTML 负责表单和结果展示，脚本负责实际文件操作。浏览器中没有 Node.js、shell 或任意文件读写接口；传回 `files[].path` 也不等于获得浏览器读取该路径内容的能力。

### 读取上下文

宿主在页面脚本运行前注入 `window.menumate`，无需安装 SDK：

```js
const bridge = window.menumate;
const ctx = bridge.context;
document.querySelector('#files').textContent =
  ctx.files.map(file => file.name).join('\n');
```

| 字段 | 类型与用途 |
| --- | --- |
| `files` | `[{name, path}]`，宿主捕获的选中项；`path` 是绝对路径 |
| `title` / `locale` | 当前显示名称、App 语言，如 `en` 或 `zh-Hans` |
| `parameters` | 上次选择记住的参数对象；首次及试运行为空对象 |
| `variant` / `runID` | 子菜单值（没有时为空字符串）、窗口会话 ID |
| `isTestRun` / `testRoot` | 是否试运行、样本根目录；普通运行的 `testRoot` 为空字符串 |

普通浏览器直接打开 HTML 时没有这个桥接对象。入门包会显示提示，可用于查看布局；完整执行必须在 MenuMate 中验证。

### 提交参数、接收结果和关闭

以下代码假定页面已有 `#run`、`#close`、`#mode`、`#remember`、`#result` 元素；[完整 HTML](../examples/selection-info-pack/ui/report.html)可以直接运行。

```js
document.querySelector('#run').addEventListener('click', () => {
  const mode = document.querySelector('#mode').value;
  document.querySelector('#run').disabled = true;
  bridge.submit({mode}, document.querySelector('#remember').checked);
});
window.addEventListener('menumate:result', ({detail}) => {
  const {exitCode, stdout, stderr, timedOut} = detail;
  document.querySelector('#result').textContent =
    [timedOut ? '超时' : `退出码 ${exitCode}`, stdout, stderr].join('\n');
});
document.querySelector('#close').addEventListener('click', () => bridge.cancel());
```

`submit(parameters, remember = false)` 发送 JSON 对象，**不返回 Promise**。根节点不能是数组、字符串或 `null`；编码后最多 65,536 字节。只传业务选项，不传 shell 命令或可切换执行目标的动作 ID。每个窗口只能提交一次；需要重跑时重新打开动作，不能在收到结果后再次调用 `submit()`。

宿主接受提交时就会保存 `remember: true` 的参数，因此脚本后来失败也会记住本次选项。它按动作保存，不按文件保存；取消和试运行不保存。

`menumate:result` 在脚本结束后发送一次，不是流式输出；`stdout`、`stderr` 各最多返回前 32,000 个字符。用 `textContent` 展示，避免把文件名或脚本输出作为 HTML 执行。宿主在提交前拒绝无效参数时，只显示原生窗口错误，不会产生脚本结果事件，页面应先校验自己的表单数据。

`cancel()` 在提交前或执行结束后关闭窗口；执行过程中不会终止脚本，关闭请求也会被忽略。脚本的时限由 `timeoutSeconds` 控制。

## 脚本读取 HTML 参数

入门包用 macOS 自带的 `plutil` 读取 JSON 字段，无须额外安装 Python、Node.js 或 jq：

```zsh
mode=$(print -rn -- "${MENUMATE_INPUT:-}" |
  /usr/bin/plutil -extract mode raw -expect string -o - - 2>/dev/null) || {
  print -u2 -- 'Expected a string mode'; exit 2
}
[[ "$mode" == names || "$mode" == paths ]] || {
  print -u2 -- 'mode must be names or paths'; exit 2
}
for item in "$@"; do
  if [[ "$mode" == names ]]; then print -r -- "${item:t}"
  else print -r -- "$item"
  fi
done
```

实际文件见 [report.zsh](../examples/selection-info-pack/actions/report.zsh)。页面限制选项不能代替脚本验证；记住的参数可能来自旧版本。数值需验证类型和范围，枚举需验证允许值。需要调用外部工具时，用参数数组传值，避免命令拼接。

普通脚本动作的 `MENUMATE_INPUT` 默认为 `{}`；HTML 提交后该变量包含参数 JSON。定位包内资源使用 `${0:A:h}`，不要假定工作目录就是包目录；工作目录取决于所选文件。数据、模板、语言及终端等环境变量见[脚本环境契约](pack-spec.zh.md#脚本环境契约)。脚本的 stdin 已关闭，交互参数应从 HTML 或环境变量读取。

## 资源、依赖和多语言

CSS、JavaScript、图片等页面资源放在 HTML 入口目录或子目录，用相对路径引用。HTTP(S) 资源和 WebSocket 会被阻止，不要依赖 CDN；页面跳转、iframe 和新窗口也不属于支持的交互方式。需要多步表单时在同一页面内切换视图。

需要联网的业务可由脚本实现，并明确说明所访问的服务、发送的数据和所需凭据。宿主不会自动安装扩展包的运行依赖，也不提供密钥管理；优先使用系统已有工具，必要依赖要在脚本启动时检测并返回可理解的错误。

包名、说明、动作名分别使用 `localizedNames`、`localizedDescriptions`、`localizedTitles`：

```json
"localizedTitles": {"en": "Selected file info", "zh-Hans": "所选文件信息"}
```

HTML 根据 `context.locale` 翻译自己的表单，脚本可读取 `MENUMATE_LOCALE` 翻译结果。默认 `name`、`title` 仍是必填回退文本；子菜单固定值不会自动翻译。

## 调试与发布

终端先验证参数和输出，不必每次经过 Finder。以下命令接着使用上面的 `pack_dir`：

```sh
/bin/zsh "$pack_dir/actions/names.zsh" "$pack_dir/manifest.json"
MENUMATE_INPUT='{"mode":"paths"}' /bin/zsh \
  "$pack_dir/actions/report.zsh" "$pack_dir/manifest.json"
```

第一条应输出 `manifest.json`，第二条应输出它的完整路径。`mode` 改成不支持的值应返回非零退出码。继续在 App 试运行，检查多选、带空格文件名、超时、取消、记住参数及中英文界面。试运行生成的资源位于独立临时目录，但脚本仍拥有当前用户权限，并非进程沙箱。

| 现象 | 检查位置 |
| --- | --- |
| Finder 中没有动作 | 是否启用、Finder 扩展是否生效、所选目录是否受支持，以及 `targets` / `utis` 是否匹配 |
| HTML 空白或缺少样式 | schema 是否为 2、入口是否存在、资源是否在允许目录内、是否用了远程资源或跳转 |
| 页面点击无结果 | 表单校验、参数大小、原生窗口底部错误；是否已经提交过一次 |
| 找不到命令或附属文件 | 用户机器的运行依赖、PATH；用脚本位置定位包内文件 |
| 修改后安装版本没变 | 原仓库是否已提交；检查更新并审查差异；更新前关闭该包弹窗、等待动作完成 |

发布时将包文件放在独立仓库根目录并提交，用户即可通过仓库地址导入。GitHub 仓库添加 `menumate-pack` topic 可被社区入口发现。一个仓库是一整个包，包内动作独立启停，更新和卸载作用于整个包；目前没有独立安装仓库子目录、依赖自动安装或按动作版本更新的约定。

进一步参考：[完整规范](pack-spec.zh.md)、[带子菜单的脚本示例](../examples/example-pack/)、[图片压缩与转换 HTML 示例](../examples/image-tools-pack/)。
