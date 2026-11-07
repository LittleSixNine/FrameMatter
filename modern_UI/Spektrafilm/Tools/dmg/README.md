# DMG 安装窗口方案

2026-11-07 确认：**后续打包采用方案六，替代方案四。** 本目录现已同步方案六的位图和生成流程；打包直接使用已确认的 TIFF，不会自动重绘。

## 已确认的外观

- 背景逻辑尺寸 660×440 pt；PNG 分别为 660×440 和 1320×880 px，`background.tiff` 包含 1×、2× 两层。
- 标题使用 Sigma Serif Headline，28 pt，额外字间距 **1.5 pt**，水平居中。
- 不显示“拖动到 Applications 安装”等底部中文提示。
- 箭头位于浅色区域中心：浅色区域 y=110…432，箭头中心为 **(330, 271) pt**。
- 浅色区域采用现有 Metal 引擎的胶片颗粒，取均匀色块开启／关闭颗粒的渲染差值，灰度化后低对比度合成；不再采用程序绘制的圆点颗粒。
- 颗粒取样为 Portra 400 / Portra Endura、16 mm，自动曝光与 glare 关闭；Retina 目标标准差为 1.8/255。保留已保存的真实颗粒样本，以复现已确认的纹理。
- FrameMatter.app 和 Applications 必须仍是 Finder 内的真实文件图标，名称使用 Finder 字体，不画入背景。

## 方案来源与生成流程

仓库根目录下的私人方案路径：

`pravite/dmg-options/06-engine-film-grain/Tools/dmg/`

本次接入及后续维护：

1. 本目录已用该目录的 `background.png`、`background@2x.png`、`background.tiff` 替换同名资源。`Tools/package.sh` 直接使用本目录的 TIFF，将其复制到 DMG 隐藏目录 `.background`。
2. 已同步方案六的生成流程，避免旧 `render-background.swift` 再生成方案四。方案六通过 `generate-grain.py` 调用现有引擎，`engine-grain.npy` 保存本次纹理；普通打包直接使用已生成的图片，不需要运行引擎、Python 或安装字体。
3. DMG 外观段仅调整图标布局：两图标保持左／右放置，中心与箭头对齐为 **(180, 271)** 和 **(480, 271) pt**。窗口、隐藏资源、图标视图及布局落盘检查沿用现有方式；不改变构建、版本、签名或公证逻辑。
4. 不将私人字体文件复制进公开资源或安装包。字体仅在本地生成图片时使用，不安装到系统。

方案六已验证引擎颗粒输出、图片尺寸、标题区域和铜橙色条保持。每次打包后须重新挂载最终压缩镜像，确认背景、图标与箭头对齐、文件名清晰、Applications 链接有效，并将测试产物与实际 Finder 截图保存到 `pravite`。

## 字体授权边界

用户已选择按个人非商业用途制作本地方案。调查记录见 `pravite/dmg-options/02-sigma-serif/字体调查.txt`；适马网站的个人／家庭非营利用途条款，不等于已确认允许公开分发使用该字体制作的软件背景。对外发布前仍需核对适用许可；本方案确认不代表字体公开分发授权已完成。

## 重新生成

仅在需要重绘时执行，普通打包无需这些依赖：

```sh
DMG_TITLE_FONT_PATH=/path/to/your/licensed/font.woff \
  /path/to/python-with-numpy-pillow Tools/dmg/generate-grain.py [output-directory]
```

默认复用跟踪的 `engine-grain.npy`，保证已确认纹理不随引擎更新而变化。只有该样本缺失时才重新调用本机引擎采样；不会安装字体或下载依赖。脚本同时生成1×/2× PNG与双层TIFF。
