# Balanced highlight candidate v1 — frozen research equation

Experimental starting point, frozen before rendering on 2026-11-09. It is not a new product default or a material-profile change. No image names, faces, camera IDs or per-photo tuning enter the equation.

Use the existing balanced meter's actual scene-linear luminance sample `Y` and its unchanged result `Eb`. The meter sees the same decoded/geometrically framed, at-most-1600-long-edge input the engine uses today. `g = 0.184`; clamp luminance below `g/4096` as the existing meter does. `S(t) = clamp(t,0,1)^2 × (3 − 2 × clamp(t,0,1))`.

```
wE = S((Eb − 3) / 2)
A  = mean S((log2(Y / g) + Eb − 2.5) / 0.5)
wA = S((A − 0.005) / 0.025)
Et = 2.5 − log2(P99.5(Y) / g)
R  = wE × wA × clamp(Eb − Et, 0, 6)
Ec = Eb − R
```

The lift gate begins above +3 EV and reaches full weight at +5 EV. The soft endangered-highlight area counts luminance at gray +2.5..3.0 stops after balanced exposure. An area at or below 0.5% has no influence; 3% reaches full weight. The high-percentile target uses the existing meter's exact integer rank `995×(N−1)/1000`. Reduction is capped at 6 EV. These are one fixed set of research thresholds, not validated defaults.

A uniformly dark scene raised to gray has zero endangered-highlight area. A few isolated points occupying no more than 0.5% cannot trigger the area gate. Ordinary lift at or below +3 EV cannot trigger the lift gate. The equation does not identify subjects or claim that every backlit portrait is safe; stronger-lift portraits with broad highlights can still be affected and require review.

`engine/tools/balanced_highlight_candidate.hpp` contains the pure function. `engine/tests/balanced_highlight_candidate.cpp` checks negative controls, positive response, reduction bounds, smooth joins and invalid input. The ordinary engine has no include or call to this research header.

`engine/tools/build_balanced_highlight_experiment.py [temporary-root]` builds a separate app from the **current working tree**, including uncommitted source changes. It accepts only an absent or completely empty temporary directory, rejecting symbolic-link roots and previous partial builds. It records HEAD, source hashes, tracked diff hash and actual executable/debug-dylib/bundled-Metal hashes in the temporary build's manifest. It needs only the repository's normal Xcode/Metal tools and Python 3.11+ standard library (for hashlib.file_digest), and can run from a clean clone after the normal bundle prerequisites are present. It has no dependency on earlier research directories or photos.

Only the temporary engine copy includes the function. Its real `Pipeline::measure_meter_evs` changes the balanced return value when `FRAMEMATTER_BALANCED_CANDIDATE=1`, auto exposure is enabled and the selected method is `balanced`. The supplied meter result flows through the ordinary `negative_for` injection into `node_auto_exposure`. Exposure compensation, scene placement, material curves, saved recipes and Layer 2 are unchanged. Other methods and manual exposure retain their original behavior. Ordinary builds contain none of the experiment integration.

Launch the experimental app separately for each mode, with fresh Foundation homes and source copies. Set `FRAMEMATTER_BALANCED_CANDIDATE=0` for baseline and `=1` for the candidate. Optionally set `FRAMEMATTER_BALANCED_CANDIDATE_TRACE` to a private JSONL output path. Each actual meter calculation records the equation version, sample size, area, weights, percentile, target, original/candidate/selected EV, user compensation, method and whether the candidate was applied. JSON traces are not written into sidecars or recipes.

The temporary app gives **both** experiment modes a versioned print-cache stamp, separate from the ordinary product stamp and each other. The temporary engine's meter cache key also includes the process mode, auto-exposure enabled flag and selected meter method, so manual/other-method → balanced transitions cannot reuse the wrong variant. The mode is a launch-time switch; changing environment variables inside a running process is not a supported user flow. Independent homes/cold renders and traces remain necessary evidence that output did not come from a shared cache.

The +3..+5 EV activation interval is continuous but need not preserve small exposure differences: with full highlight-area and reduction weights, a half-stop change in the balanced result may produce a much larger output shift. Before considering a default, test bracketed exposures of the same scene and mixed bright-sign/dark-face scenes, alongside isolated lights and uniformly dark scenes. This limitation does not justify retuning the frozen equation to these three examples.

## Independent fixed meter-offset experiment

The same isolated build tool also supports a separate four-arm study through `FRAMEMATTER_BALANCED_METER_OFFSET_EV`: exactly `0`, `-0.5`, `-1` or `-1.5`. An unset variable leaves this experiment inactive. Its equation is simply `Eb_after = Eb_before + offset`; it does not alter the frozen candidate-v1 equation above. Supplying an offset together with candidate v1 enabled is rejected, as are values outside these four literal choices.

Only auto exposure with the balanced method consumes this offset. It is added to the actual `measure_meter_evs` balanced result, before the normal engine injects that result into the film's auto-exposure node. It is not a compensation edit or an output exposure operation. Keep compensation at zero and render the zero-offset baseline with the same new build. The normal solve must leave compensation unchanged; verify the effective parameters and the downstream `applied_auto_exposure` trace, rather than trusting the reported meter alone. Manual mode and other meter methods retain their existing output.

The meter-cache key and versioned Swift print stamp both include the offset string (including the distinction between unset and explicit zero), in addition to the candidate mode and existing parameter identity. Every arm still requires its own fresh home, source copy and trace. Trace records retain the original meter, `before_offset_ev`, `meter_offset_ev`, `after_offset_ev`, `offset_requested` and `offset_applied`; the actual auto-exposure node separately records its consumed EV, compensation and pixel dimensions. No experimental flag is stored in a recipe. Ordinary builds continue to exclude all integration.

This four-arm study preserves the product's default grain, halation and glare. Unseeded glare means small pixel differences are not solely evidence of the meter change. It is an exposure-placement experiment, not proof of recoverable RAW clipping or a proposed product default. Narrow validation covers exact offsets and cache switching through the real built engine, manual/other-meter invariance, mutually exclusive modes, and the original v1 behavior with no offset. It does not require the unrelated full UI suite.

## RAW shadow and re-metering study

The isolated research build also accepts `FRAMEMATTER_RAW_SHADOW_BIAS=0`. An unset value preserves the decoder's initial shadow bias; any other explicit value is rejected. It changes only `CIRAWFilter.shadowBias`, after the ordinary decoder settings and before `outputImage`. Both independently constructed linear and display filters receive the override. The film still consumes the ordinary `decodeRAW.linear` output. Baseline exposure, decoder exposure, white balance and the ordinary linear-look controls remain unchanged. `FRAMEMATTER_RAW_DECODER_TRACE` records the source and look, initial/effective shadow bias, baseline/exposure, as-shot/effective temperature and tint, decoder version and the effective tone controls for each filter.

`FRAMEMATTER_BALANCED_FROZEN_EV` freezes the actual balanced meter result to a finite EV within ±32. It is rejected with candidate v1 or the fixed-offset experiment; manual and other meter methods do not consume it. It is an input to the normal auto-exposure node, not an exposure-compensation or exported-JPEG edit. A fresh original-RAW candidate run supplies the frozen value for the shadow-zero isolation arm. The combined arm instead re-measures the shadow-zero decoded input and applies the unchanged v1 equation. Its trace retains original balanced EV, percentile, highlight area, weights, target, reduction and selected EV, while the downstream trace records the consumed EV and actual print-exposure-compensation flag.

The experimental print stamp and meter key include shadow and frozen identities. The RAW decode cache schema is deliberately unchanged: **shadow identity is fixed at process launch, and every arm requires a fresh source copy, fresh Foundation home and an observed new linear decoder trace**. Switching shadow mode in a running process with existing decoded objects is unsupported. The research integration is copied into the temporary tree only; ordinary product sources and defaults remain unchanged.

The three-arm batch is defined before export: A = original RAW interpretation plus candidate v1; B = shadow bias zero with the actual meter frozen to that photograph's final A EV; C = shadow bias zero, a fresh balanced measurement, then the same frozen v1 equation. B is a diagnostic intervention that isolates decoded-input changes at one fixed film placement; it is not a proposed product strategy. All three use the real CLI/Session/Exporter route, zero user compensation, ordinary default effects and 1024-pixel-long-edge JPEGs. Private per-arm manifests retain hashes, effective parameters, decoder facts, native-size applied-EV records and independent home/source identities.

The reproducible private batch entry is `pravite/02-研究与实验/RAW阴影与重新测光-20261109/run.py`; its build provenance names the actual temporary app. The adjacent `verify-engine.py` links the engine from that application's C++ objects and exercises 13 narrow controls: frozen-EV cache transitions and actual node consumption, manual/average invariance, invalid/combined mode rejection and the unchanged candidate-without-freeze response. `engine-check.json` records PASS and the actual trace confirms zero user compensation and disabled product print-exposure compensation. These are opt-in research checks, not a replacement for the normal product test gates.

The same build also passed the existing 16 actual-engine fixed-offset compatibility controls, including all four offsets and cache return, manual/six other-meter invariance, original candidate response and offset/candidate refusal (`verify-offset-compatibility.py`, `offset-compatibility.json` in the private batch). This specifically checks that adding the frozen diagnostic entrance did not change the earlier offset experiment.

A real-CLI invalid-shadow control (`FRAMEMATTER_RAW_SHADOW_BIAS=1`) returned a decode failure and wrote no preview, while the same source completed all three valid arms. The public CLI reports its ordinary generic decode error rather than the private guard's detailed message.
