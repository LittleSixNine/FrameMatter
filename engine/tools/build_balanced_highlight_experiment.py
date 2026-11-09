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
patch(pipeline, '#include <chrono>', '#include <chrono>\n#include <cstdlib>\n#include <fstream>\n#include "../../tools/balanced_highlight_candidate.hpp"')
patch(pipeline, '    out = exposure_evs_from(Y, sh, sw);', r'''    out = exposure_evs_from(Y, sh, sw);
    const char* candidate_mode = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE");
    const bool candidate_enabled = candidate_mode && std::strcmp(candidate_mode, "1") == 0;
    const char* offset_request = std::getenv("FRAMEMATTER_BALANCED_METER_OFFSET_EV");
    const auto parsed_offset = research::balanced_meter_offset(offset_request);
    if (!parsed_offset || (candidate_enabled && offset_request)) {
        error = "research meter offset must be 0, -0.5, -1 or -1.5 and cannot be combined with candidate v1";
        return false;
    }
    const double meter_offset = *parsed_offset;
    const char* trace_path = std::getenv("FRAMEMATTER_BALANCED_CANDIDATE_TRACE");
    if (candidate_enabled || offset_request || trace_path) {
        const auto candidate = research::balanced_highlight_candidate(Y, out.balanced);
        const bool apply = candidate_enabled && candidate.valid && params_.camera.auto_exposure &&
                           params_.camera.auto_exposure_method == "balanced";
        if (apply) out.balanced = candidate.candidate_ev;
        const double before_offset = out.balanced;
        const bool apply_offset = offset_request && params_.camera.auto_exposure &&
                                  params_.camera.auto_exposure_method == "balanced";
        if (apply_offset) out.balanced = before_offset + meter_offset;
        if (trace_path) {
            Json trace = Json::object();
            trace.set("event", Json(std::string("meter_candidate")));
            trace.set("equation", Json(std::string(offset_request ? "balanced-meter-offset-v1" : "balanced-highlight-v1")));
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
    key += ";ae=" + values.at("auto_exposure").dump() + ";method=" + values.at("auto_exposure_method").dump();''')
session = root / 'modern_UI/Spektrafilm/Spektrafilm/Model/Session.swift'
patch(session, '        let stamp = p.wire.map { "\\($0.name)=\\($0.value)" }.joined(separator: ";")', r'''        let experimentMode = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_CANDIDATE"] == "1" ? "1" : "0"
        let meterOffset = ProcessInfo.processInfo.environment["FRAMEMATTER_BALANCED_METER_OFFSET_EV"] ?? "unset"
        let stamp = "balanced-highlight-v1;mode=\(experimentMode);meter-offset-v1=\(meterOffset);" + p.wire.map { "\($0.name)=\($0.value)" }.joined(separator: ";")''')

project = root / 'modern_UI/Spektrafilm'
run(['clang++', '-std=c++20', '-O2', root / 'engine/tests/balanced_highlight_candidate.cpp', '-o', root / 'candidate-check'])
run([root / 'candidate-check'])
run(['bash', root / 'engine/build.sh', 'bundle'])
run([sys.executable, project / 'Tools/gen-project.py'])
with (root / 'app-build.log').open('w') as log:
    run(['xcodebuild', '-project', project / 'Spektrafilm.xcodeproj', '-scheme', 'Spektrafilm',
         '-configuration', 'Debug', '-derivedDataPath', root / 'DerivedData', 'build'], stdout=log, stderr=subprocess.STDOUT)

app = root / 'DerivedData/Build/Products/Debug/FrameMatter.app'
binary = app / 'Contents/MacOS/FrameMatter'
manifest = {
    'equation': 'balanced-highlight-v1', 'source_kind': 'current working tree',
    'meter_offset_experiment': 'balanced-meter-offset-v1', 'supported_meter_offsets_ev': [0, -0.5, -1, -1.5],
    'head': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
    'tracked_diff_sha256': hashlib.sha256(subprocess.check_output(['git', '-C', str(source), 'diff', 'HEAD', '--', 'engine', 'modern_UI'])).hexdigest(),
    'source_sha256': {str(f.relative_to(source)): hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()
                      for f in [source / 'engine/src/pipeline/pipeline.cpp', source / 'engine/src/pipeline/engine.cpp',
                                source / 'engine/tools/balanced_highlight_candidate.hpp',
                                source / 'engine/tools/build_balanced_highlight_experiment.py',
                                source / 'engine/tests/balanced_highlight_candidate.cpp',
                                source / 'modern_UI/Spektrafilm/Spektrafilm/Model/Session.swift']},
    'binary': str(binary), 'binary_sha256': hashlib.file_digest(binary.open('rb'), 'sha256').hexdigest(),
    'runtime_files_sha256': {str(f.relative_to(app)): hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()
                             for f in [binary, binary.with_name('FrameMatter.debug.dylib'),
                                       *sorted((app / 'Contents/Resources').rglob('spektrafilm.metallib'))] if f.is_file()},
    'ordinary_source_modified': False,
}
(root / 'experiment-build.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps(manifest, indent=2))
