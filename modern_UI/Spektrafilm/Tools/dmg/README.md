# DMG 打包资源

从仓库根目录运行 `modern_UI/Spektrafilm/Tools/package.sh --local` 可生成本地安装包。公开分发构建使用不带 `--local` 的模式，并受脚本中的资源完整性、签名及公证检查约束。

打包直接使用本目录已生成的 `background.tiff`；两份 PNG 是 1×／2× 预览。窗口为 660×440 pt，应用与 Applications 链接由 Finder 排布，不画入背景。普通打包不需要重绘背景、安装字体或运行 Python。

需要重绘时，在 `modern_UI/Spektrafilm/` 下运行：

```sh
DMG_TITLE_FONT_PATH=/path/to/your/licensed/font.woff \
  /path/to/python-with-numpy-pillow Tools/dmg/generate-grain.py [output-directory]
```

所用字体必须具有相应使用授权；字体文件不随源码或安装包分发。生成流程默认复用 `engine-grain.npy`；只在样本缺失时调用引擎重新采样。修改背景后应重新挂载最终 DMG，核验背景、图标位置和 Applications 链接。

历史设计方案和本地确认记录仅保存在 `pravite/开发记录/modern_UI/Spektrafilm/Tools/dmg/README.md`，不随公开源码分发。
