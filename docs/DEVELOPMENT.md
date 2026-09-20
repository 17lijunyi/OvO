# 开发说明

## 环境与构建

使用支持 Swift Testing 的 Swift 6 工具链、macOS 15 或更新 SDK。应用最低部署目标为 macOS 14；苹果系统翻译通过可用性检查仅在 macOS 15+ 启用。

```sh
./scripts/build-app.sh        # Release，输出 dist/OvO.app
./scripts/build-app.sh debug  # Debug
./scripts/test.sh             # Swift Testing
```

测试脚本兼容 Xcode 与仅安装 Apple Command Line Tools 的环境。预编译发布包目前只提供 Apple Silicon 版本；未验证 Intel Mac 运行效果。

## 签名

默认由 `scripts/sign-app.py` 创建固定的本机开发身份，跨构建复用，减少更新后系统权限和钥匙串授权失效的问题。

首次构建在 `~/Library/Application Support/Ovo/Signing` 创建独立签名钥匙串，密码文件权限为 0600。签名结束后锁定该钥匙串并恢复原有钥匙串搜索列表，不向登录钥匙串导入私钥、不添加系统受信根证书。请保留此目录以维持后续构建身份，切勿上传其中的文件。

已有证书时，可通过环境变量 `OVO_SIGNING_IDENTITY` 指定证书名称或指纹。本机开发签名不等于 Apple Developer ID 签名或公证；公开发行包当前尚未公证。

## 项目结构

- `Sources/Ovo/Core`：翻译请求、服务配置、钥匙串、历史存储和语言模型。
- `Sources/Ovo/Platform`：全局快捷键、跨应用取词、系统截图和本机 OCR。
- `Sources/Ovo`：SwiftUI/AppKit 入口、浮窗、设置、历史及系统翻译集成。
- `Tests/OvoTests`：单元测试、模拟 HTTP、平台回归与本机 OCR 测试。
- `Resources`：应用元数据、图标和服务标志。
- `scripts`：构建、图标生成、签名和测试脚本。
- `docs/images`：README 封面及四张真实桌面截图。

## 数据与请求

API Key 保存在系统钥匙串中。启动和设置状态检查只查询密钥是否存在，首次翻译或测试连接时才读取正文；成功后仅在本次进程缓存。DeepSeek 与自定义 API 使用独立条目。

历史保存原文、译文、时间、收藏状态和服务名称；旧历史兼容迁移。写入失败不更新内存记录；损坏文件保留，不自动覆盖。清理和删除操作需要确认。

截图优先读取系统生成的临时文件；按住 Control 导致截图转存剪贴板时，只读取本次截图期间新产生且稳定的图片，不使用旧剪贴板内容。临时文件在识别后清理。

兼容 API 不发送 DeepSeek 专用的 `thinking` 参数。远程只接受 HTTPS，允许本机 HTTP，拒绝 HTTP 重定向，以避免意外转发密钥及文本。

## 验证范围

1.0.0（构建 15）包含 75 项自动化测试，覆盖语言方向、请求格式、模拟 HTTP 响应、取消、历史存储与迁移、服务切换、截图输出解析及中英文 OCR。

已在开发机验证苹果系统中英双向翻译与首次语言包下载、自定义 API 的本机模拟服务连接、应用启动和设置界面。自动化测试不调用用户的真实 API Key。

跨应用划词与截图选区的完整交互仍需在目标 Mac 上授权后手动验证；不同应用的可访问性支持、快捷键占用和系统权限状态均会影响使用。未对所有第三方兼容 API、Intel Mac 或全部受支持 macOS 版本完成实机验证。
