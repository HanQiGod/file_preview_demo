# file_preview_demo

基于文章内容整理的 Flutter 文件预览示例，重点演示两条实现路线：

- 全能型插件：`universal_file_viewer`
- 自由组合型：`photo_view` + `mini_pdf_epub_viewer` + 本地文本 / CSV 渲染 + `open_filex` 兜底

## Demo 内容

- 预置本地示例文件：图片、Markdown、CSV、TXT
- 远程 PDF 预览示例
- 系统文件选择器接入
- Android 权限演示
- 同一份文件在两种预览策略之间切换

## 运行方式

```bash
cd file_preview_demo
flutter pub get
flutter run
```

## 说明

- AndroidManifest 已补充 `INTERNET`、`READ_EXTERNAL_STORAGE`、`READ_MEDIA_*` 权限声明。
- 组合方案里没有直接接入 Office 专用内核，当前以说明卡片 + 外部打开作为兜底。
- 如果你要继续扩展业务版，可以在组合方案的 Office 分支接入 `flutter_office_viewer` 或 Android X5 方案。
