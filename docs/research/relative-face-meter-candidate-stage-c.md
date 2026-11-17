# 阶段C：有限补回与空全图分区补检，单版冻结

2026-11-10，在实施/本轮渲染之前冻结。v1仍是当前候选；以用户认可的旧含脸v2为起点，组合已冻结阶段A补回和阶段B唯一通用检测回退，不采用v2.1，不改任何曝光公式常数，不按16图回调。

完整保留阶段A：shadow0、原baseline/as-shot WB/decoder exposure0、旧场景2EV、旧confidence≥.6及原meter宽高≥16px资格、最大有效脸/平局规则、中心60%中位、gray+.5EV目标/Eb+1上限、成功测脸后向Eb补回最多.5EV。Portra400/Supra、comp0、产品print exposure compensation=false及默认效果不变。

唯一新增独立选项 `FRAMEMATTER_FACE_TILE_FALLBACK=1`，默认关闭，仅允许v2.2-restore模式。先在原1600长边显示CGImage按revision3/`.up`成功完成全图检测；原始faces数组非空则逐值保留原框，不因不合格而回退。仅成功且原始数组为空时，对同CGImage四个固定60%分区直接crop，不放大、不重新解码/调色、不读阶段B预存框。

分区顺序外层y=0,.4，内层x=0,.4。名义bottom-left `[x,y,.6,.6]`；实际top-left像素矩形：

```
rect = CGRect(x:x*W, y:(1-y-.6)*H, width:.6*W, height:.6*H)
         .integral.intersection(fullPixelRect)
roi = [rect.minX/W, 1-rect.maxY/H, rect.width/W, rect.height/H]
mapped = [roi.x+local.x*roi.w, roi.y+local.y*roi.h,
          local.w*roi.w, local.h*roi.h]
```

每区新Vision请求revision3、`.up`。保留所有mapped框及置信度，按请求顺序拼接，不去重/NMS/挑框；原旧引擎在原meter尺寸上裁切/判资格/选最大框，不能用分区尺寸或显示1067替代meter1066。文件、crop或请求失败直接报错，不能伪造空检测。

记录原始全图框、每区实际像素rect/ROI/局部框/映回框/revision和是否触发回退，双侧缓存stamp包含新开关；源/home冷隔离，新实际原Y及所有metadata保存。原默认关闭的旧模式不变，正式app/engine/src/default不改，仅工具向新临时树注入。

实施前root独立预测相对阶段A只有14+.5EV（约.5945）、15+1EV（约1.1723）、16+.5778EV（约.8618）；其余不变，包括02/06。预测只用于核验，真正新渲染必须重新解码/检测/取Y。15/16选中框置信度约.613/.607，靠近.6边界；不换框、不调阈值。正确检测不保证成片更好，14/15亮部代价必须展示。

三臂均shadow0：旧含脸v2字节参考 / 阶段A有限补回字节参考 / 本次组合新native全尺寸消费后1024 sRGB JPEG。沿用固定ROI，16群像不变；15在看新图之前按阶段B既存选中框中心60%冻结ROI，14不手选优化。记录L*/Δa*/Δb*/ΔE00；颗粒/随机glare/JPEG限制细微像素归因，不据亮度接近宣称肤色保持。
