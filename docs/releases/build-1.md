# FrameMatter Build 1

FrameMatter 首次独立发布。基于 Hanze Qiu 的 SpektraLab 和 Andrea Volpato 的 spektrafilm，保留上游署名、许可与完整提交历史。

## 功能

- 颗粒：开放强度、粒子面积与柔和度，沿用 spektrafilm 颗粒模型。
- 日期后背：四款 DSEG7 字体与点阵字体，扩展日期／时间格式、自设时间、字段间距、135 边距，以及日时分冒号／下划线选项。
- 划痕与灰尘：齿孔摩擦、边缘痕迹、局部漏光与高光；112 份灰度尘粒／纤维素材，可调整并随机更换分布。
- 135 全宽曝光：画面覆盖齿孔之间的区域，保留镂空齿孔和边码。
- 独立 FrameMatter 品牌、新图标、居中 README，以及按 `build-N` 整数标签检查更新。

## 下载与运行环境

- `FrameMatter-Build-1-arm64.dmg`
- Apple silicon（M 系列芯片），macOS 15 或以上；不含 Intel、Windows 或 Linux 安装包。
- 应用内部版本为 `1.0.0`，构建号为 `1`，对外显示 **Build 1**。
- 本发布使用本地 ad-hoc 签名，未进行 Developer ID 签名和 Apple 公证。签名完整性通过不等于 Gatekeeper 认可；下载后的首次打开可能被 macOS 拦截。
- 完整源码和构建方法位于本仓库；应用与引擎采用 GPL-3.0-or-later，配置及第三方素材保留各自许可。

## 验证范围

- macOS 应用完整测试：599 项，73 项因外部素材缺失跳过，0 失败。
- 整数构建号更新检查：10 项通过，覆盖数值比较、无更新、无效标签及网络失败。
- 全新 Release 构建及实际应用图标读取通过；当前齿孔漏光的 Metal 输出检查通过。
- 未进行完整外部相机素材覆盖，也未在另一台 Mac 上验证安装。
