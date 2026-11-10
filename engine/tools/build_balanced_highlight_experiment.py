#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the opt-in research meter in a separate tree; never patch product sources."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

if sys.version_info < (3, 11):
    raise SystemExit('this research build tool requires Python 3.11 or newer')

source = Path(__file__).resolve().parents[2]
requested = Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/framematter-meter-candidate').expanduser()
if requested.is_symlink():
    raise SystemExit('the experiment root must not be a symbolic link')
root = requested.resolve()
if root == source or source in root.parents:
    raise SystemExit('the experiment root must be outside the source checkout')
if root.exists():
    if not root.is_dir() or any(root.iterdir()):
        raise SystemExit('experiment root must be absent or empty; choose a fresh temporary directory')
else:
    root.mkdir(parents=True)

def run(args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)

def patch(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f'expected exactly one integration point in {path.name}')
    path.write_text(text.replace(old, new))

ignore = shutil.ignore_patterns('build', 'DerivedData', '.git', 'xcuserdata', '__pycache__')
shutil.copytree(source / 'modern_UI/Spektrafilm', root / 'modern_UI/Spektrafilm', ignore=ignore)
shutil.copytree(source / 'engine', root / 'engine',
                ignore=shutil.ignore_patterns('build', 'resources', '__pycache__'))
shutil.copytree(source / 'engine/resources', root / 'engine/resources',
                ignore=shutil.ignore_patterns('local_light_leaks', 'local_aging_textures'))

pipeline = root / 'engine/src/pipeline/pipeline.cpp'
patch(pipeline, '#include <chrono>', '#include <chrono>\n#include <cstdlib>\n#include <fstream>\n#include "../../tools/balanced_highlight_candidate.hpp"\n#include "../../tools/relative_face_meter_candidate.hpp"')
patch(pipeline, '    out = exposure_evs_from(Y, sh, sw);', r'''    out = exposure_evs_from(Y, sh, sw);
    const char* candidate_mode = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE");
    const bool candidate_enabled = candidate_mode && std::strcmp(candidate_mode, "1") == 0;
    const char* relative_mode = std::getenv("FRAMEMATTER_RELATIVE_FACE_CANDIDATE");
    const bool relative_enabled = relative_mode && std::strcmp(relative_mode, "1") == 0;
    const char* scene_mode = std::getenv("FRAMEMATTER_RELATIVE_SCENE_CANDIDATE");
    const bool scene_enabled = scene_mode && std::strcmp(scene_mode, "1") == 0;
    if (scene_enabled && relative_enabled) { error = "scene and face candidates are mutually exclusive"; return false; }
    const char* conservative_mode = std::getenv("FRAMEMATTER_CONSERVATIVE_RELATIVE_CANDIDATE");
    const bool conservative_enabled = conservative_mode && std::strcmp(conservative_mode, "1") == 0;
    if (conservative_enabled && (relative_enabled || scene_enabled)) { error = "conservative, scene and face candidates are mutually exclusive"; return false; }
    const char* restore_mode = std::getenv("FRAMEMATTER_FACE_RESTORE_CANDIDATE");
    const bool restore_enabled = restore_mode && std::strcmp(restore_mode, "1") == 0;
    if (restore_enabled && (relative_enabled || scene_enabled || conservative_enabled)) { error = "face restore and other research candidates are mutually exclusive"; return false; }
    const bool relative_apply = (relative_enabled || scene_enabled || conservative_enabled || restore_enabled) && params_.camera.auto_exposure && params_.camera.auto_exposure_method == "balanced";
    const char* offset_request = std::getenv("FRAMEMATTER_BALANCED_METER_OFFSET_EV");
    const auto parsed_offset = research::balanced_meter_offset(offset_request);
    if (!parsed_offset || (candidate_enabled && offset_request)) {
        error = "research meter offset must be 0, -0.5, -1 or -1.5 and cannot be combined with candidate v1";
        return false;
    }
    const char* frozen_request = std::getenv("FRAMEMATTER_BALANCED_FROZEN_EV");
    char* frozen_end = nullptr;
    const double frozen_ev = frozen_request ? std::strtod(frozen_request, &frozen_end) : 0;
    if (frozen_request && (!*frozen_request || *frozen_end || !std::isfinite(frozen_ev) ||
                           std::abs(frozen_ev) > 32 || candidate_enabled || offset_request)) {
        error = "research frozen EV must be finite within +/-32 and cannot be combined with candidate or offset";
        return false;
    }
    if ((relative_enabled || scene_enabled || conservative_enabled || restore_enabled) && (candidate_enabled || offset_request || frozen_request)) {
        error = "relative face candidate cannot be combined with v1, offset or frozen EV";
        return false;
    }
    const double meter_offset = *parsed_offset;
    const char* trace_path = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE_TRACE");
    if (candidate_enabled || relative_enabled || scene_enabled || conservative_enabled || restore_enabled || offset_request || frozen_request || trace_path) {
        const auto candidate = research::balanced_highlight_candidate(Y, out.balanced);
        const bool apply = candidate_enabled && candidate.valid && params_.camera.auto_exposure &&
                           params_.camera.auto_exposure_method == "balanced";
        if (apply) out.balanced = candidate.candidate_ev;
        const double before_offset = out.balanced;
        const bool apply_offset = offset_request && params_.camera.auto_exposure &&
                                  params_.camera.auto_exposure_method == "balanced";
        if (apply_offset) out.balanced = before_offset + meter_offset;
        const bool apply_frozen = frozen_request && params_.camera.auto_exposure &&
                                  params_.camera.auto_exposure_method == "balanced";
        if (apply_frozen) out.balanced = frozen_ev;
        research::RelativeFaceMeter relative;
        Json face_info;
        if (relative_apply) {
            if (!params_.io.geometry.is_identity()) {
                error = "relative face experiment requires full-frame neutral geometry"; return false;
            }
            if (scene_enabled) {
                relative = research::relative_face_meter_candidate(Y,sw,sh,candidate.original_ev,{});
            } else {
            const char* face_path = std::getenv("FRAMEMATTER_BALANCED_FACE_INFO");
            const char* face_source = std::getenv("FRAMEMATTER_BALANCED_FACE_SOURCE");
            if (!face_path || !face_source) { error = "relative face experiment requires face info and source identity"; return false; }
            std::ifstream face_file(face_path);
            const std::string contents((std::istreambuf_iterator<char>(face_file)), std::istreambuf_iterator<char>());
            if (!face_file || !Json::parse(contents, face_info, error)) {
                error = "relative face info missing, unreadable or invalid: " + error; return false;
            }
            const auto& boxes = face_info.at("faces");
            const double dw = face_info.at("linear_width").as_double(), dh = face_info.at("linear_height").as_double();
            if (face_info.at("source_path").as_string() != face_source || !boxes.is_array() ||
                dw <= 0 || dh <= 0 || std::abs(dw/dh-double(sw)/sh)>2.0/sh ||
                face_info.at("display_width").as_double()!=dw || face_info.at("display_height").as_double()!=dh) {
                error = "relative face info has mismatched source or geometry"; return false;
            }
            std::vector<research::MeterFaceBox> faces;
            for (const auto& face : boxes.items()) {
                for (const char* key : {"x", "y", "width", "height", "confidence"}) {
                    if (!face.at(key).is_number() || !std::isfinite(face.at(key).as_double())) {
                        error = "relative face box has missing or nonfinite fields"; return false;
                    }
                }
                faces.push_back({face.at("x").as_double(), face.at("y").as_double(),
                                 face.at("width").as_double(),face.at("height").as_double(),face.at("confidence").as_double()});
            }
            relative = restore_enabled ? research::face_restored_relative_meter_candidate(Y,sw,sh,candidate.original_ev,faces) :
                conservative_enabled ? research::conservative_relative_meter_candidate(Y,sw,sh,candidate.original_ev,faces) :
                research::relative_face_meter_candidate(Y,sw,sh,candidate.original_ev,faces);
            }
            if (!relative.valid) { error = "relative face meter received invalid sample"; return false; }
            if (params_.camera.auto_exposure && params_.camera.auto_exposure_method == "balanced") out.balanced=relative.candidate_ev;
        }
        if (trace_path) {
            Json trace = Json::object();
            trace.set("event", Json(std::string("meter_candidate")));
            trace.set("equation", Json(std::string(restore_enabled ? "relative-face-v2.2-restore" : conservative_enabled ? "conservative-relative-v2.1" : scene_enabled ? "relative-scene-v2" : relative_enabled ? "relative-face-v2" : (offset_request ? "balanced-meter-offset-v1" : "balanced-highlight-v1"))));
            trace.set("face_restore_enabled", Json(restore_enabled));
            trace.set("conservative_relative_enabled", Json(conservative_enabled));
            trace.set("relative_scene_enabled", Json(scene_enabled));
            trace.set("relative_face_enabled", Json(relative_enabled));
            trace.set("relative_face_applied", Json(relative_apply));
            if (relative_apply) {
                Json stats=Json::object();
                stats.set("equation", Json(std::string(restore_enabled ? "relative-face-v2.2-restore" : conservative_enabled ? "conservative-relative-v2.1" : scene_enabled ? "relative-scene-v2" : "relative-face-v2")));
                stats.set("original_balanced_ev", Json(relative.original_ev));
                stats.set("candidate_ev", Json(relative.candidate_ev));
                stats.set("scene_ev", Json(relative.scene_ev));
                stats.set("highlight_area", Json(relative.area));
                stats.set("area_weight", Json(relative.area_weight));
                stats.set("p995_y", Json(relative.p995_y));
                stats.set("highlight_excess_ev", Json(relative.highlight_excess));
                stats.set("reduction_ev", Json(relative.reduction_ev));
                if (restore_enabled) {
                    stats.set("before_restore_ev",Json(relative.before_restore_ev));
                    stats.set("face_restore_ev",Json(relative.face_restore_ev));
                }
                if (conservative_enabled) {
                    Json eligible=Json::array();
                    for (int index:relative.eligible_faces) eligible.push(Json(double(index)));
                    stats.set("eligible_face_indices",eligible);
                    stats.set("face_cap_present",Json(relative.face_applied));
                    stats.set("face_cap_dominant",Json(relative.reduction_ev<relative.scene_reduction_ev));
                    stats.set("scene_reduction_ev",Json(relative.scene_reduction_ev));
                } else {
                stats.set("face_measured", Json(relative.face_applied));
                stats.set("face_bound_dominant", Json(relative.face_applied && relative.face_bound_ev>relative.scene_ev));
                stats.set("selected_face", Json(double(relative.selected_face)));
                stats.set("face_median_y", Json(relative.face_median_y));
                stats.set("face_target_ev", Json(relative.face_target_ev));
                stats.set("face_bound_ev", Json(relative.face_bound_ev));
                stats.set("face_x0",Json(double(relative.x0)));stats.set("face_x1",Json(double(relative.x1)));
                stats.set("face_y0",Json(double(relative.y0)));stats.set("face_y1",Json(double(relative.y1)));
                }
                stats.set("face_info",face_info);
                trace.set("relative_face",stats);
            }
            if (const char* sample_dir = std::getenv("FRAMEMATTER_METER_SAMPLE_DIR")) {
                const std::string sample_path = std::string(sample_dir) + "/Y-" +
                    std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".f64";
                std::ofstream sample(sample_path, std::ios::binary);
                sample.write(reinterpret_cast<const char*>(Y.data()), std::streamsize(Y.size()*sizeof(double)));
                sample.flush();
                if (!sample) { error = "meter Y sample could not be written"; return false; }
                trace.set("sample_path", Json(sample_path));
                trace.set("sample_encoding", Json(std::string("native little-endian IEEE754 float64, row-major Y")));
            }
            trace.set("frozen_requested", Json(frozen_request != nullptr));
            trace.set("frozen_applied", Json(apply_frozen));
            trace.set("frozen_ev", Json(frozen_ev));
            trace.set("raw_shadow_bias_override", Json(std::string(std::getenv("FRAMEMATTER_RAW_SHADOW_BIAS") ? std::getenv("FRAMEMATTER_RAW_SHADOW_BIAS") : "unset")));
            trace.set("enabled", Json(candidate_enabled));
            trace.set("applied", Json(apply));
            trace.set("valid", Json(candidate.valid));
            trace.set("sample_width", Json(double(sw)));
            trace.set("sample_height", Json(double(sh)));
            trace.set("original_balanced_ev", Json(candidate.original_ev));
            trace.set("candidate_ev", Json(candidate.candidate_ev));
            trace.set("selected_balanced_ev", Json(out.balanced));
            trace.set("offset_requested", Json(offset_request != nullptr));
            trace.set("offset_applied", Json(apply_offset));
            trace.set("meter_offset_ev", Json(meter_offset));
            trace.set("before_offset_ev", Json(before_offset));
            trace.set("after_offset_ev", Json(out.balanced));
            trace.set("highlight_area", Json(candidate.highlight_area));
            trace.set("lift_weight", Json(candidate.lift_weight));
            trace.set("area_weight", Json(candidate.area_weight));
            trace.set("p995_y", Json(candidate.p995_y));
            trace.set("target_ev", Json(candidate.target_ev));
            trace.set("reduction_ev", Json(candidate.reduction_ev));
            trace.set("auto_exposure", Json(params_.camera.auto_exposure));
            trace.set("method", Json(params_.camera.auto_exposure_method));
            trace.set("exposure_compensation_ev", Json(params_.camera.exposure_compensation_ev));
            std::ofstream file(trace_path, std::ios::app);
            file << trace.dump() << '\n';
            if (!file) { error = "experiment meter trace could not be written"; return false; }
        }
    }''')
patch(pipeline, '    last_ae_ev_ = ev;', r'''    last_ae_ev_ = ev;
    if (const char* trace_path = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE_TRACE")) {
        Json trace = Json::object();
        trace.set("event", Json(std::string("applied_auto_exposure")));
        trace.set("method", Json(params_.camera.auto_exposure_method));
        trace.set("auto_exposure_ev", Json(ev));
        trace.set("exposure_compensation_ev", Json(params_.camera.exposure_compensation_ev));
        trace.set("print_exposure_compensation", Json(params_.enlarger.print_exposure_compensation));
        trace.set("width", Json(double(in.w)));
        trace.set("height", Json(double(in.h)));
        std::ofstream file(trace_path, std::ios::app);
        file << trace.dump() << '\n';
        if (!file) { error = "experiment exposure trace could not be written"; return false; }
    }''')
engine = root / 'engine/src/pipeline/engine.cpp'
patch(engine, '    for (const char* name : kMeterKeyFields) key += values.at(name).dump() + ";";', r'''    for (const char* name : kMeterKeyFields) key += values.at(name).dump() + ";";
    const char* mode = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE");
    key += std::string("balanced-highlight-v1;") + ((mode && std::strcmp(mode, "1") == 0) ? "1" : "0");
    const char* offset = std::getenv("FRAMEMATTER_BALANCED_METER_OFFSET_EV");
    key += std::string(";meter-offset-v1=") + (offset ? offset : "unset");
    for (const char* name : {"FRAMEMATTER_BALANCED_FROZEN_EV", "FRAMEMATTER_RAW_SHADOW_BIAS", "FRAMEMATTER_RELATIVE_FACE_CANDIDATE", "FRAMEMATTER_RELATIVE_SCENE_CANDIDATE", "FRAMEMATTER_CONSERVATIVE_RELATIVE_CANDIDATE", "FRAMEMATTER_FACE_RESTORE_CANDIDATE", "FRAMEMATTER_BALANCED_FACE_INFO", "FRAMEMATTER_BALANCED_FACE_SOURCE"}) {
        const char* value = std::getenv(name);
        key += std::string(";") + name + "=" + (value ? value : "unset");
    }
    key += ";ae=" + values.at("auto_exposure").dump() + ";method=" + values.at("auto_exposure_method").dump();''')
session = root / 'modern_UI/Spektrafilm/Spektrafilm/Model/Session.swift'
patch(session, '        let stamp = p.wire.map { "\\($0.name)=\\($0.value)" }.joined(separator: ";")', r'''        let experimentMode = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_CANDIDATE"] == "1" ? "1" : "0"
        let meterOffset = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_METER_OFFSET_EV"] ?? "unset"
        let shadow = ProcessInfo.processInfo.environment["FRAMEMATTER_RAW_SHADOW_BIAS"] ?? "unset"
        let frozen = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_FROZEN_EV"] ?? "unset"
        let relative = ProcessInfo.processInfo.environment["FRAMEMATTER_RELATIVE_FACE_CANDIDATE"] ?? "unset"
        let scene = ProcessInfo.processInfo.environment["FRAMEMATTER_RELATIVE_SCENE_CANDIDATE"] ?? "unset"
        let conservative = ProcessInfo.processInfo.environment["FRAMEMATTER_CONSERVATIVE_RELATIVE_CANDIDATE"] ?? "unset"
        let restore = ProcessInfo.processInfo.environment["FRAMEMATTER_FACE_RESTORE_CANDIDATE"] ?? "unset"
        let faceInfo = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_FACE_INFO"] ?? "unset"
        let stamp = "relative-face-v2.2-restore=\(restore);conservative-relative-v2.1=\(conservative);relative-scene-v2=\(scene);relative-face-v2=\(relative);face-info=\(faceInfo);raw-shadow-meter-v1;shadow=\(shadow);frozen=\(frozen);balanced-highlight-v1;mode=\(experimentMode);meter-offset-v1=\(meterOffset);" + p.wire.map { "\($0.name)=\($0.value)" }.joined(separator: ";")''')

# Research-only RAW override, after ordinary settings and before either outputImage.
decoder = root / 'modern_UI/Spektrafilm/Spektrafilm/Import/ImageDecoder.swift'
patch(decoder, '        let asShotTemperature = Double(filter.neutralTemperature)', '        let initialShadowBias = filter.shadowBias\n        let asShotTemperature = Double(filter.neutralTemperature)')
patch(decoder, '        return (filter, asShotTemperature, asShotTint)', r'''        let environment = ProcessInfo.processInfo.environment
        let shadowRequest = environment["FRAMEMATTER_RAW_SHADOW_BIAS"]
        if let shadowRequest {
            guard shadowRequest == "0" else {
                throw NSError(domain: "FrameMatterResearch", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "research shadow override accepts only 0"])
            }
            filter.shadowBias = 0
        }
        if let tracePath = environment["FRAMEMATTER_RAW_DECODER_TRACE"] {
            let facts: [String: Any] = [
                "event": "raw_decoder", "source": url.path,
                "look": look == .linear ? "linear" : "display",
                "shadow_override": shadowRequest ?? "unset",
                "initial_shadow_bias": initialShadowBias, "actual_shadow_bias": filter.shadowBias,
                "baseline_exposure_ev": filter.baselineExposure, "decoder_exposure_ev": filter.exposure,
                "as_shot_temperature": asShotTemperature, "as_shot_tint": asShotTint,
                "actual_temperature": filter.neutralTemperature, "actual_tint": filter.neutralTint,
                "decoder_version": filter.decoderVersion,
                "boost_amount": filter.boostAmount, "boost_shadow_amount": filter.boostShadowAmount,
                "gamut_mapping": filter.isGamutMappingEnabled, "local_tone_map": filter.localToneMapAmount,
                "extended_dynamic_range": filter.extendedDynamicRangeAmount]
            var data = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
            data.append(10)
            if !FileManager.default.fileExists(atPath: tracePath) {
                guard FileManager.default.createFile(atPath: tracePath, contents: nil) else {
                    throw NSError(domain: "FrameMatterResearch", code: 2)
                }
            }
            let file = try FileHandle(forWritingTo: URL(fileURLWithPath: tracePath))
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: data)
        }
        return (filter, asShotTemperature, asShotTint)''')

# Vision supplies only normalized boxes; luminance statistics stay in the engine.
patch(decoder, 'import CoreImage\n', 'import CoreImage\nimport Vision\n')
patch(decoder, '        return DecodedImage(linear: try settings.perspective.applying(to: linear),', r'''        if ProcessInfo.processInfo.environment["FRAMEMATTER_RELATIVE_FACE_CANDIDATE"] == "1" || ProcessInfo.processInfo.environment["FRAMEMATTER_CONSERVATIVE_RELATIVE_CANDIDATE"] == "1" || ProcessInfo.processInfo.environment["FRAMEMATTER_FACE_RESTORE_CANDIDATE"] == "1" {
            let environment = ProcessInfo.processInfo.environment
            guard let facePath = environment["FRAMEMATTER_BALANCED_FACE_INFO"],
                  environment["FRAMEMATTER_BALANCED_FACE_SOURCE"] == url.path else {
                throw NSError(domain: "FrameMatterResearch", code: 3)
            }
            let framedDisplay = try settings.perspective.applying(to: display)
            let framedLinear = try settings.perspective.applying(to: linear)
            guard framedDisplay.extent.integral == framedLinear.extent.integral else {
                throw NSError(domain: "FrameMatterResearch", code: 4)
            }
            let extent = framedDisplay.extent.integral
            let scale = min(1, 1600 / max(extent.width, extent.height))
            let width = Int((extent.width * scale).rounded()), height = Int((extent.height * scale).rounded())
            let preview = framedDisplay.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: .init(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let cg = context.createCGImage(preview, from: CGRect(x: 0, y: 0, width: width, height: height),
                                               format: .RGBA8, colorSpace: space) else { throw Failure.unsupported(url) }
            let request = VNDetectFaceRectanglesRequest()
            let start = Date()
            try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            let duration = Date().timeIntervalSince(start)
            let faces = (request.results ?? []).map { face -> [String: Any] in
                let box = face.boundingBox
                return ["x": box.minX, "y": box.minY, "width": box.width, "height": box.height,
                        "confidence": face.confidence]
            }
            let previewPath = facePath + ".png"
            guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: previewPath) as CFURL,
                        UTType.png.identifier as CFString, 1, nil) else { throw Failure.unsupported(url) }
            CGImageDestinationAddImage(destination, cg, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.unsupported(url) }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let info: [String: Any] = ["equation": "relative-face-v2", "source_path": url.path,
                "source_filename": url.lastPathComponent, "source_size": attributes[.size] ?? 0,
                "linear_width": Int(framedLinear.extent.integral.width), "linear_height": Int(framedLinear.extent.integral.height),
                "display_width": Int(extent.width), "display_height": Int(extent.height),
                "preview_width": width, "preview_height": height, "preview_path": previewPath,
                "vision_revision": request.revision, "vision_duration_seconds": duration,
                "box_coordinates": "normalized bottom-left, upright CGImage orientation up",
                "faces": faces]
            try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]).write(to: URL(fileURLWithPath: facePath), options: .atomic)
        }
        return DecodedImage(linear: try settings.perspective.applying(to: linear),''')

project = root / 'modern_UI/Spektrafilm'
run(['clang++', '-std=c++20', '-O2', root / 'engine/tests/balanced_highlight_candidate.cpp', '-o', root / 'candidate-check'])
run([root / 'candidate-check'])
run(['clang++', '-std=c++20', '-O2', root / 'engine/tests/relative_face_meter_candidate.cpp', '-o', root / 'relative-face-check'])
run([root / 'relative-face-check'])
run(['clang++', '-std=c++20', '-O2', root / 'engine/tests/conservative_relative_meter_candidate.cpp', '-o', root / 'conservative-check'])
run([root / 'conservative-check'])
run(['clang++', '-std=c++20', '-O2', root / 'engine/tests/face_restore_meter_candidate.cpp', '-o', root / 'face-restore-check'])
run([root / 'face-restore-check'])
run(['bash', root / 'engine/build.sh', 'bundle'])
run([sys.executable, project / 'Tools/gen-project.py'])
with (root / 'app-build.log').open('w') as log:
    run(['xcodebuild', '-project', project / 'Spektrafilm.xcodeproj', '-scheme', 'Spektrafilm',
         '-configuration', 'Debug', '-derivedDataPath', root / 'DerivedData', 'build'], stdout=log, stderr=subprocess.STDOUT)

app = root / 'DerivedData/Build/Products/Debug/FrameMatter.app'
binary = app / 'Contents/MacOS/FrameMatter'
manifest = {
    'equation': 'balanced-highlight-v1', 'source_kind': 'current working tree',
    'relative_face_experiment': 'relative-face-v2', 'relative_scene_experiment': 'relative-scene-v2', 'conservative_relative_experiment': 'conservative-relative-v2.1', 'face_restore_experiment': 'relative-face-v2.2-restore',
    'raw_shadow_meter_experiment': 'raw-shadow-meter-v1', 'supported_shadow_override': [0], 'frozen_meter_ev_range': [-32, 32],
    'meter_offset_experiment': 'balanced-meter-offset-v1', 'supported_meter_offsets_ev': [0, -0.5, -1, -1.5],
    'head': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
    'tracked_diff_sha256': hashlib.sha256(subprocess.check_output(['git', '-C', str(source), 'diff', 'HEAD', '--', 'engine', 'modern_UI'])).hexdigest(),
    'source_sha256': {str(f.relative_to(source)): hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()
                      for f in [source / 'engine/src/pipeline/pipeline.cpp', source / 'engine/src/pipeline/engine.cpp',
                                source / 'engine/tools/balanced_highlight_candidate.hpp',
                                source / 'engine/tools/relative_face_meter_candidate.hpp',
                                source / 'engine/tests/relative_face_meter_candidate.cpp',
                                source / 'engine/tests/conservative_relative_meter_candidate.cpp',
                                source / 'engine/tests/face_restore_meter_candidate.cpp',
                                source / 'engine/tools/build_balanced_highlight_experiment.py',
                                source / 'engine/tests/balanced_highlight_candidate.cpp',
                                source / 'modern_UI/Spektrafilm/Spektrafilm/Model/Session.swift',
                                source / 'modern_UI/Spektrafilm/Spektrafilm/Import/ImageDecoder.swift']},
    'binary': str(binary), 'binary_sha256': hashlib.file_digest(binary.open('rb'), 'sha256').hexdigest(),
    'runtime_files_sha256': {str(f.relative_to(app)): hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()
                             for f in [binary, binary.with_name('FrameMatter.debug.dylib'),
                                       *sorted((app / 'Contents/Resources').rglob('spektrafilm.metallib'))] if f.is_file()},
    'ordinary_source_modified': False,
}
(root / 'experiment-build.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps(manifest, indent=2))
