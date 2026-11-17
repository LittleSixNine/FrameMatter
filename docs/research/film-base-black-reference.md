# Film-base grain and the shared black reference

2026-11-11. The optional uniform film-base fog introduced in `c81c5fe` was
withdrawn by `1c36bcb`. Independent factory-lettering exposure remains available.
No replacement processing or new default was introduced by this study.

The product goal is a rebate that remains a black reference alongside picture
shadows. Adding light only outside the gate raises that region independently;
its improved grain visibility does not establish a better match to this goal.
Measured material profiles must not be changed to hide this presentation issue.

## Controlled comparison

Two protected RAW copies, a seascape and a night street, were rendered at native
resolution with Portra 400 / Supra Endura. Decode, exposure, geometry and seeds
were fixed within each photograph. Glare was off. A private diagnostic build used
the internal exact grain sampler; the product's stochastic default was unchanged.

The three arms were the restored baseline (grain amount 1), existing shared grain
amount 2, and the rejected maximum base-fog exposure as a counterexample. Grain
particle area 0.2 and blur 0.65 were fixed. Grain-off controls isolate the final
output's grain residual; fixed clean-rebate and adjacent-picture ROIs exclude
perforations and lettering. Statistics use decoded relative linear D50 luminance,
not RGB channel differences or display luminance in cd/m².

Shared grain amount 2 increased rebate high-frequency residual by about 2.2×,
but its visible texture remained weak. Adjacent picture-shadow residual increased
about 2.4–2.6×. The rebate/shadow median relationship was broadly retained, while
the picture's dark distribution widened. This is insufficient evidence to adopt
the change: it increases picture grain without adequately solving rebate visibility.

The rejected base fog raised rebate median relative Y from approximately 0.00348
to 0.00599, above the selected adjacent shadows in both photographs. Its visible
texture comes with the unwanted regional separation, so it remains rejected.

## Limits and decision

Keep the restored processing and defaults. Do not promote shared grain amount 2
as a solution, add independent rebate exposure, or synthesize local noise on the
basis of these results. A common monotonic output mapping preserves an existing
luminance order; it cannot undo an order already inverted by local exposure.
Any future shadow mapping must assess picture detail as well as rebate texture.

The black-reference goal concerns visible regional relationships, not a guarantee
that every grain-bearing rebate pixel is darker than every picture pixel. Near an
output floor, obvious two-sided grain and an absolute minimum cannot be obtained
without a tradeoff. This two-photo study does not calibrate physical granularity,
prove equivalence across display scales, or cover every film/paper combination.
Original RGB16 renders and private comparison records remain outside public source.
