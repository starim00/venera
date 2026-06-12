# venera

[English](README.md)

Venera 是一个支持本地漫画和网络漫画阅读的漫画阅读器。

本仓库是基于原 Venera 项目的 fork。由于上游项目已停止维护，本 fork 用于持续维护和功能实验。

## 功能

- 阅读本地漫画
- 使用 JavaScript 创建漫画源
- 从网络漫画源阅读漫画
- 管理漫画收藏
- 下载漫画
- 在漫画源支持时查看评论、标签和其他漫画信息
- 在漫画源支持时登录、评论、评分和执行其他交互操作

### Fork 新增功能

- 阅读器页级译文面板，基于 OpenAI-compatible 多模态 chat completions 接口。
- 手动翻译当前阅读页或多页同屏内容，并通过底部抽屉展示译文结果。
- 本地译文缓存，缓存键包含来源、漫画、章节、页码范围、图片哈希、目标语言和模型。
- 页面翻译设置支持 endpoint、API key、模型、目标语言、系统提示词、恢复默认提示词，以及用于自建端点的忽略证书错误选项。

页面翻译只会在阅读器中手动触发。触发翻译时，当前页图片会发送到用户配置的模型服务端点。

## 从源码构建

1. 克隆仓库
2. 安装 Flutter，参考 [flutter.dev](https://flutter.dev/docs/get-started/install)
3. 安装 Rust，参考 [rustup.rs](https://rustup.rs/)
4. 针对目标平台构建，例如：`flutter build apk`

## 创建新的漫画源

参考 [Comic Source](doc/comic_source.md)

## 致谢

### 标签翻译

[EhTagTranslation](https://github.com/EhTagTranslation/Database)

漫画标签的中文翻译来自该项目。

## Headless Mode

参考 [Headless Doc](doc/headless_doc.md)
