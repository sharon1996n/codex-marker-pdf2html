# codex-marker-pdf2html

这是一个给 Codex 使用的 skill，用来稳定调用本地的 [Marker](https://github.com/datalab-to/marker) / `marker-pdf`，把 PDF 等文档转换成适合阅读和后续处理的 HTML。

## 一句话使用

安装这个 skill 后，直接对 Codex 说：

```text
用 codex-marker-pdf2html 把这个 PDF 转成 HTML
```

或者更自然一点：

```text
用 marker 把 E:\path\paper.pdf 转成 HTML
```

如果你没有指定输出目录，skill 首次使用时会询问是否默认保存到用户文档目录下的 `MarkerOutput`。之后也可以在聊天里直接指定新的保存位置。

## 目的

这个 skill 主要是为了方便、稳定地使用本地 Marker，帮助使用 Codex 等大模型方法阅读 PDF 文档，减少大模型“假读”的风险。

它的基本思路是：

1. 先把 PDF 转成可检查、可打开、可复用的 HTML。
2. 再让 Codex 基于转换后的真实内容进行阅读、总结、问答或后续加工。

这样比直接让大模型“看一个 PDF 文件名然后总结”更可靠。

HTML 格式对读者也比较友好：

- 可以直接用浏览器打开。
- 可以使用浏览器自带的翻译功能。
- 图片、表格和正文通常会被保存在同一输出目录中，方便人工检查。
- 后续接入其它 skills 时，可以更快、更准确地生成论文总结、阅读笔记或 PPT。

## 这个 skill 做什么

- 自动发现本机已有的 Marker / `marker-pdf` 环境。
- 如果找不到 Marker，可以按规则安装一个本地环境。
- 转换前检测当前 Marker Python 是否支持 GPU；如果 CUDA 可用，就优先使用 GPU。
- 默认输出 HTML，也支持在明确要求时输出 Markdown、JSON 或 chunks。
- 转换后检查主要输出文件、元数据和图片资源是否存在。

## Marker 致谢

本 skill 是 Codex 的编排层，不包含 Marker 源码。实际文档转换能力来自开源项目 Marker：

- Repository: https://github.com/datalab-to/marker
- Package: `marker-pdf`
- License: GPL-3.0-or-later

如果重新分发 Marker 本体、打包后的环境或包含 Marker 的安装产物，请保留 Marker 的版权和许可证声明，并遵守其许可证条款。
