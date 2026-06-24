.PHONY: bootstrap gen test test-presets build run reset-ext release

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@[ -f Local.xcconfig ] || cp Local.xcconfig.template Local.xcconfig

gen: bootstrap
	xcodegen generate

test:
	cd Core && swift test

# 预设脚本的确定性行为测试(不依赖 Finder/剪贴板)
test-presets:
	@zsh scripts/test-presets.sh

build: gen
	xcodebuild -project MenuMate.xcodeproj -scheme MenuMate -configuration Debug \
	  -derivedDataPath build build

run: build
	open build/Build/Products/Debug/MenuMate.app

# 右键菜单/Finder 扩展又没了时跑一下:清理僵尸注册 + 重注册 + 重启 pkd/Finder
reset-ext:
	@chmod +x scripts/dev-reset-extension.sh && scripts/dev-reset-extension.sh

# 签名 + 公证 + dmg + Sparkle 签名(需 Developer ID 证书与公证凭据,见 docs/RELEASING.md)
# 用法: make release VERSION=1.0.0
release: gen
	@chmod +x scripts/release.sh && scripts/release.sh $(VERSION)
