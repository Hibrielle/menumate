# 参与 MenuMate 开发

[English](CONTRIBUTING.md) · 简体中文

MenuMate 由 SwiftUI / AppKit 主应用、Finder Sync 扩展和 MenuMateCore Swift Package 组成。优先保持扩展轻量，把可独立验证的模型与逻辑放入 Core。

## 开发环境

需要 macOS 13+、Xcode 16+ 和 Homebrew。

```sh
make bootstrap
make gen
make test
make test-presets
make test-packs
make test-history # 隔离验证执行历史和错误处理
make test-storage # 验证配置写入失败及扩展包中断恢复
make build
```

`Local.xcconfig` 和生成的 Xcode 工程不纳入版本控制。不要提交个人签名配置、证书或本地应用数据。构建产物位于 `build/Build/Products/Debug/MenuMate.app`。

## 测试与验收

Core 回归测试位于 `Core/Tests/MenuMateCoreTests/`。包管理集成测试用临时 Git 仓库和隔离配置编译真实 PackManager，不修改个人安装数据。测试应按稳定 ID 或 `presetKey` 查找动作，不依赖系统语言或用户目录。

按变更运行相应检查。修改执行、匹配、持久化或扩展包协议时应补行为测试；修改界面时检查真实 App 的中英文、浅深色和窄窗口。构建成功不等于 Finder 端到端通过，不要用模拟桥接测试代替实际 HTML 窗口的执行验证。

## 国际化

使用抽象键和 String Catalog：主界面位于 `App/Localizable.xcstrings`，Core 位于 `Core/Sources/MenuMateCore/Localizable.xcstrings`，Finder 扩展使用自己的目录。

```swift
Text(String(localized: "execLog.empty"))
String(format: String(localized: "execLog.exitCode"), code)
```

自定义组件接收 `String` 时，调用方应明确本地化。新增面向用户的文案同时提供英文与简体中文。HTML 页面通过 `window.menumate.context.locale` 获取语言，作者应自行提供页面翻译。

## 动作与扩展包

新增内置预设时，将脚本放入 `App/PresetScripts/`，在 `MenuConfig.defaultSeed()` 注册稳定 `presetKey`，补充 Core 文案及受影响的测试。遵守[脚本环境契约](docs/pack-spec.zh.md#脚本环境契约)，优先通过 `"$@"` 处理路径。

可选功能优先参考[脚本示例包](examples/example-pack/)和[HTML 示例包](examples/image-tools-pack/)。一个包可包含多个动作，HTML 动作必须显式使用 schema 2。涉及更新审查时，依赖文件和清单变化也必须纳入验证。

## 提交与评审

从 `main` 创建功能分支，按可独立审查的变化组织提交。PR 说明应写清问题、用户可见行为和实际完成的验证；UI 变化附界面证据，并明确未验收的边界。不要把构建通过描述为全部功能通过。

贡献按项目 [MIT 许可](LICENSE) 提供。正式发布步骤见[发布流程（英文）](docs/RELEASING.md)。
