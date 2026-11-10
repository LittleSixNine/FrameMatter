# v2.1 保守测光研究版：一次冻结方程

2026-11-10，在阶段1归因之后、实施与看新图之前冻结。v1仍是当前候选；v2.1只是一版探索性研究，不是产品默认，也不宣称在这16张上最优。

输入为原RAW scene-linear样本Y与现有balanced读数Eb。**不设置shadow override**：保留原shadowBias、baseline exposure、decoder exposure0及as-shot WB。Portra 400 / Supra、comp0、产品print exposure compensation=false及默认效果不变。只改变场景放置，不改材料、RAW解码或局部色调。

`g=.184`；Y floor与现有meter相同，`g/4096`。`S(t)=clamp(t,0,1)^2*(3-2*clamp(t,0,1))`，P99.5采用整数rank `995*(N-1)/1000`。

```
T = log2(max(Y,g/4096)/g) + Eb
A = mean S((T-2.5)/.5)
wA = S((A-.005)/.025)
H = log2(P99.5(max(Y,g/4096))/g) + Eb - 2.5
h = max(H,0)
Rscene = wA * min(6, h, h*h/2)
R = min(Rscene,.25)    if any eligible detected face
R = Rscene            otherwise
E = Eb - R
```

相对高光余量h约1EV时预算约0.5EV、h=2时2EV；更高风险保留至6EV能力，同时`min(h)`不让二次项产生超过目标余量的额外降档。0.25EV人脸上限与二次预算是一次探索假设，非感光材料测量值。普通场景/漏检脸仍可能偏暗；原RAW14等无有效脸样本可能显著更暗，属于预设反例，不能看图后改参。

Vision仍只检测实际upright/perspective-adjusted显示解码、1600长边的矩形。所有框裁至unit square；confidence≥.6，实际meter样本中宽与高均≥16px者合格。**不再选最大脸**，只要任意合格脸便收紧全局降档预算；记录所有检测框与合格索引。无肤色分割，不读脸部亮度，不设gray目标，不抬曝光。误检脸可能妨碍高光保护，漏检脸只有普通场景预算保护；不能保证同时保全背光主体和亮部。

不读取绝对Eb门槛、文件身份、v1输出、手工ROI或逐图偏好。对不触及floor、检测框固定的输入尺度变化，场景量保持曝光等变；Vision检测自身不作该保证。只允许full-frame中性几何。有效框为空时合法走无脸分支，检测/文件失败必须报错。

A/B/C完整看图：A为v1当前候选原JPEG字节参考，B为旧含脸v2原JPEG字节参考（明确其shadow0），C为原RAW v2.1本轮真实全尺寸引擎消费后1024 sRGB JPEG。阶段1原balanced/v1/纯场景入口单独保留。默认随机glare限制细微像素归因。

实现仅由工具在新的隔离临时树注入；不覆盖旧v1/v2模式或构建。每张记录实际原始Y、decoder/native EV、全部框及合格索引、缓存隔离、源/输出/runtime哈希；从Y独立重算冻结方程。只运行这一版，不按16图回调。
