# v2.2-face：旧含脸v2有限补回，阶段A冻结公式

2026-11-10，在实现与本轮渲染之前冻结。v1仍是当前候选；用户认可并继续优化的研究起点是旧含脸v2，不是v2.1。本阶段仅检验一项曝光补回假设，不修复检测、不与其他研究组合，不按16图调参。

完整保留旧v2：RAW shadowBias=0，baseline exposure、decoder exposure0及as-shot WB不变；相对高光场景规则与2EV预算不变；Vision实际upright显示解码1600长边、旧confidence/.6与meter宽高16px资格、最大有效脸与平局规则、中心60%采样、gray+.5EV脸目标与Eb+1EV上限、旧人脸提亮规则全部不变。Portra 400 / Supra、comp0、产品print exposure compensation=false、默认grain/halation/glare不变。

Eb为同一shadow0样本的原balanced读数。Eold由旧v2完整方程计算，不读取v1结果、逐图身份、手工ROI或偏好。仅在旧v2成功取得合格脸且中心样本非空时：

```
B = min(.5, max(0, Eb - Eold))
Enew = Eold + B
```

无成功测得的脸：`B=0; Enew=Eold`。旧v2已把曝光提至Eb或更高时，补回为0，保留旧提亮结果；旧E低于Eb时，新E不低于旧E且不超过Eb。0.5EV为一次冻结探索上限，不是测量常数或已验证最优值。

旧批次预测只有04 +.167957、10 +.376054、11 +.271596、12 +.5EV；其余（包括02/05/06/08/09/16）曝光原样。实际新build必须重新解码、检测、取Y并计算Eold/B/Enew，不消费旧输出或预测EV；如预测不符，先查数据/实现，不调冻结常数。

新模式仅在工具头/builder生成的隔离临时树注入，独立开关且与其他候选模式互斥。保留旧v1/v2/scene/v2.1模式、旧构建及旧图，不改正式engine/src、应用源码、产品默认或材料。冷源/home；每张保存实际decoder/native trace、全尺寸消费、全部框/旧选脸及旧脸目标、原Y与尺寸、Eold/Eb/B/Enew、源/资源/runtime/输出哈希。

完整16图为原v1/旧含脸v2字节参考与新有限补回实际全尺寸消费后1024 sRGB JPEG。v1与另两臂RAW解释不同，跨臂差不能说成纯测光单因素；同shadow0旧v2与新模式是本阶段单因素对照，仍有随机glare、颗粒/JPEG限制，不据小像素差或L*接近宣称肤色保持。报告固定ROI L*、Δa*/Δb*/ΔE00，保留全部反例。
