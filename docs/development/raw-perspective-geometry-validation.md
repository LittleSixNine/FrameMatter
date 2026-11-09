# RAW perspective: date and perforation geometry validation

Validated on 2026-11-09 using one real 7008×4672 Sony RAW copied into an isolated test workspace. No production source changed. This supplements the earlier factory-lettering check with the actual date and individual perforations.

The normal `Session` → `Exporter.export` path produced five original-size 7312×6766, 16-bit, uncompressed Display P3 TIFFs: neutral and (+12° vertical, −8° horizontal), each with date on/off, plus a repeated neutral/date-off negative control. ImageIO readback confirmed dimensions, depth and exact Display P3 ICC bytes. Film was Kodak Portra 400, paper Kodak Supra Endura; exposure was manual 0 EV, full crop, no rotation/flips, and grain/glare/halation were disabled. Both arms used the same 135 strip, white perforations, camera/frame seeds 31/47 and frame number 12. The actual date was `26 11 09`, lower right, size 0.7 and +5 EV. Sidecar snapshots confirm the fixed inputs and respective perspective/date settings.

Measurements use native TIFF coordinates, top-left origin, inclusive bounds. The tolerance was set to 2 pixels before measuring.

| Observation | Result |
| --- | --- |
| Upper and lower perforation rows | 8 holes per row; all 16 bounding boxes and centers shifted 0 px; white-hole masks identical |
| Real date exposure mask | Neutral and corrected masks, including canvas position, byte-identical; nonzero bounds `[5240,5070,6613,5263]`, center `[5926.5,5166.5]`; shift 0 px |
| Exported date on/off differences | Six strong digit cores shifted at most 1 px at edges and 0.5 px at centers; amplitude, square-root and binary registration each chose `(0,0)` |
| Repeated neutral/date-off export | Maximum channel difference 0 |
| Deliberate +5 px mask translation | Detected 5 px, exceeding the 2 px tolerance |
| Interior photograph | Mean normalized maximum RGB-channel difference 0.136565; 91.62% of sampled-region pixels exceeded 512/65535 |

The originally specified low difference threshold **did not pass**: at 512/65535 the final date-difference bounding box changed by 5 px at its top edge; at 256/65535 it changed by 25 px. The faint exposure fringe responds to the changed underlying photograph. Stronger thresholds and registration are supplementary evidence, not a retroactive pass for the original threshold.

To distinguish that photometric fringe from a geometry change, a second isolated build observed the exact date coverage buffer immediately before `spk_overscan_add_mask` uploads it. Both real RAW arms produced the same 1631×289 float mask at canvas origin `(5168,5049)`, with coverage SHA-256 `1b54b1a0ae03018b3985169fddabfbd228332458de1c3ab0ddf9a401cbe950c6`. The shader adds this exposure to the existing scene before development. All five complete TIFF files from this observer build had the same SHA-256 values as the uninstrumented run. The observer patch exists only in a temporary engine copy.

The opt-in RAW workflow ran twice with one executed test, zero failures and zero skips each time. Private evidence retains the TIFFs, sidecars, test source, observer patch, measurements, full per-hole coordinates, hashes and five inspected ROI/mask images. This checks one RAW, one material pair, one format and one nonzero angle pair; it does not claim that every final date fringe pixel is invariant or replace live-window acceptance.
