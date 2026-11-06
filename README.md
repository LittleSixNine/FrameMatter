<p align="center">
  <img src="docs/assets/framematter-icon.png" width="160" height="160" alt="FrameMatter icon">
</p>
<h1 align="center">FrameMatter</h1>

[简体中文](README.zh-CN.md)

FrameMatter is a macOS app for film and print simulation, independently developed by [LittleSixNine](https://github.com/LittleSixNine). It builds on [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) by **Hanze Qiu** and the [spektrafilm](https://github.com/andreavolpato/spektrafilm) model by **Andrea Volpato**.

The upstream application provides the spectral film/print pipeline, native C++/Metal engine, film and paper profiles, RAW workflow, half-frame pairs, export, CLI and MCP access. FrameMatter retains those foundations and adds controls for grain, date imprints and the physical appearance of a film strip.

## Added in FrameMatter

- **Grain controls:** strength, particle area and softness, exposing the existing spektrafilm grain model.
- **Date Back:** four DSEG7 LCD fonts, alongside the dot-matrix face; additional date/time formats, manually set date/time, field spacing, size and brightness controls. The 135 inset follows the picture corner-to-center diagonal, excluding the film border. Year/month/day/hour/minute/second printing is restricted to between-frame placement. Day/hour/minute can use a colon or the reference-style underlines.
- **Scratches & Dust:** sprocket-friction scratches, perforation-edge wear, perforation light leaks and narrow edge highlights. Negative-scan dust uses **112 real grayscale masks: 64 particles, 32 short fibers and 16 long fibers**. Adjust amount, size, strength, fiber ratio and border-only/whole-film coverage; **Another** changes the saved random pattern. Preview and export share the same pattern.
- **Full-width 135 exposure:** a 69.5 × 35 mm / 6×7 preset lets the image reach around and beyond the perforations, with edge markings over the exposed scene. The holes remain empty. Available under panoramic formats.
- **Film-border presentation:** white or near-black hole backing, and indented child controls under subsection headings in the left rail.

These are visual simulation controls, not calibrated reproductions of a particular camera's wear or scanner. Date Back remains unavailable on panoramic formats; scratches and dust require full-frame, half-frame or full-width 135 Film Edge.

## Build and test

Apple silicon, macOS 15+, Xcode 26.6 with the Metal toolchain. From the repository root:

```bash
engine/build.sh bundle
python3 modern_UI/Spektrafilm/Tools/gen-project.py
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath modern_UI/Spektrafilm/build/DerivedData build
```

The app is `modern_UI/Spektrafilm/build/DerivedData/Build/Products/Debug/FrameMatter.app`. The internal target/module remains `Spektrafilm`. Baked resources are tracked; the app uses no Python at runtime. Existing local settings and edit-storage paths are retained for compatibility.

```bash
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme SpektrafilmTests -configuration Debug \
  -derivedDataPath modern_UI/Spektrafilm/build/DerivedData test
```

Some tests need external camera fixtures and skip when those files are absent. A green run with skips is not full fixture coverage. See [ARCHITECTURE.md](ARCHITECTURE.md) and [the frontend notes](modern_UI/Spektrafilm/README.md) for implementation details.

[Releases](https://github.com/LittleSixNine/FrameMatter/releases) · [Issues](https://github.com/LittleSixNine/FrameMatter/issues) · [Source](https://github.com/LittleSixNine/FrameMatter)

FrameMatter builds are separate from upstream's installers and do not inherit upstream's Developer ID signature or Apple notarization. CLI/MCP access is off until enabled in Settings → Agents; that panel provides the `framematter` command and current MCP configuration.

## Credits and licenses

| Contribution | Author / source | License |
|---|---|---|
| Original application, native C++/Metal port and four black-and-white profiles | [Hanze Qiu / SpektraLab](https://github.com/JamesQiu2005/SpektraLab) | GPL-3.0-or-later; profile data retains its notices |
| Film model, measured color profiles and print LUTs | [Andrea Volpato / spektrafilm](https://github.com/andreavolpato/spektrafilm) | Code GPL-3.0-or-later; profiles/LUTs CC BY-SA 4.0 |
| FrameMatter additions | [LittleSixNine](https://github.com/LittleSixNine/FrameMatter) | GPL-3.0-or-later |
| Grayscale dust and fiber scan data | [Daniela Ivanova / Scans of film damage](https://doi.org/10.6084/m9.figshare.21803292) | CC BY 4.0; crops and extraction changes recorded in the bundle |
| Scratch-mask algorithm reference | [FilmDamageSimulator](https://github.com/daniela997/FilmDamageSimulator) | MIT |
| DSEG fonts | [Keshikan / DSEG](https://github.com/keshikan/DSEG) | SIL Open Font License 1.1 |
| Metal C++ bindings | Apple / metal-cpp | Apache-2.0 |

Full license texts and source links are available in **FrameMatter → About FrameMatter** and in the source tree. The README and application use the FrameMatter icon. FrameMatter is an independent derivative and is not an official SpektraLab or spektrafilm release. Git history and upstream attribution are preserved.
