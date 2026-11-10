// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "balanced_highlight_candidate.hpp"
#include <cstdint>

namespace spk::research {
struct MeterFaceBox {
    double x=0, y=0, w=0, h=0, confidence=0;
};
struct RelativeFaceMeter {
    bool valid=false, face_applied=false;
    double original_ev=0, candidate_ev=0, scene_ev=0, area=0, area_weight=0;
    double p995_y=0, highlight_excess=0, reduction_ev=0;
    double face_median_y=0, face_target_ev=0, face_bound_ev=0;
    int selected_face=-1;
    std::vector<int> eligible_faces;
    double scene_reduction_ev=0;
    uint32_t x0=0, y0=0, x1=0, y1=0;
};
inline RelativeFaceMeter relative_face_meter_candidate(
        const std::vector<double>& raw, uint32_t width, uint32_t height,
        double balanced_ev, const std::vector<MeterFaceBox>& faces) {
    RelativeFaceMeter r;
    r.original_ev=r.candidate_ev=r.scene_ev=balanced_ev;
    if (!width || !height || raw.size()!=size_t(width)*height || !std::isfinite(balanced_ev)) return r;
    constexpr double g=.184, floor=g/4096;
    std::vector<double> y;
    y.reserve(raw.size());
    for (double v:raw) {
        if (!std::isfinite(v)) return r;
        v=std::max(v,floor);
        y.push_back(v);
        r.area+=smoothstep01((std::log2(v/g)+balanced_ev-2.5)/.5);
    }
    r.area/=double(y.size());
    r.area_weight=smoothstep01((r.area-.005)/.025);
    auto sorted=y;
    const size_t rank=995u*(sorted.size()-1u)/1000u;
    std::nth_element(sorted.begin(),sorted.begin()+rank,sorted.end());
    r.p995_y=sorted[rank];
    r.highlight_excess=std::log2(r.p995_y/g)+balanced_ev-2.5;
    r.reduction_ev=r.area_weight*std::clamp(r.highlight_excess,0.0,2.0);
    r.scene_ev=r.candidate_ev=balanced_ev-r.reduction_ev;
    MeterFaceBox selected;
    for (size_t i=0;i<faces.size();++i) {
        auto f=faces[i];
        if (!std::isfinite(f.x)||!std::isfinite(f.y)||!std::isfinite(f.w)||!std::isfinite(f.h)||
            !std::isfinite(f.confidence)||f.confidence<.6||f.w<=0||f.h<=0) continue;
        const double right=std::clamp(f.x+f.w,0.0,1.0), top=std::clamp(f.y+f.h,0.0,1.0);
        f.x=std::clamp(f.x,0.0,1.0);
        f.y=std::clamp(f.y,0.0,1.0);
        f.w=right-f.x;
        f.h=top-f.y;
        if (f.w*width<16 || f.h*height<16) continue;
        const double area=f.w*f.h, previous=selected.w*selected.h;
        if (r.selected_face<0 || area>previous || (area==previous &&
            (f.x<selected.x || (f.x==selected.x && f.y<selected.y)))) {
            selected=f;
            r.selected_face=int(i);
        }
    }
    if (r.selected_face>=0) {
        const auto bound=[](double v,uint32_t n) {
            return uint32_t(std::clamp(std::ceil(v*n),0.0,double(n)));
        };
        r.x0=bound(selected.x+.2*selected.w,width);
        r.x1=bound(selected.x+.8*selected.w,width);
        r.y0=bound(1-selected.y-.8*selected.h,height);
        r.y1=bound(1-selected.y-.2*selected.h,height);
        std::vector<double> sample;
        for (uint32_t row=r.y0;row<r.y1;++row)
            for (uint32_t col=r.x0;col<r.x1;++col) sample.push_back(y[size_t(row)*width+col]);
        if (!sample.empty()) {
            const size_t middle=(sample.size()-1u)/2u;
            std::nth_element(sample.begin(),sample.begin()+middle,sample.end());
            r.face_median_y=sample[middle];
            r.face_target_ev=std::log2(g*std::sqrt(2.0)/r.face_median_y);
            r.face_bound_ev=std::min(r.face_target_ev,balanced_ev+1.0);
            r.candidate_ev=std::max(r.scene_ev,r.face_bound_ev);
            r.face_applied=true;
        }
    }
    r.valid=true;
    return r;
}
// Research-only v2.1: faces limit loss; their luminance never sets exposure.
inline RelativeFaceMeter conservative_relative_meter_candidate(
        const std::vector<double>& raw, uint32_t width, uint32_t height,
        double balanced_ev, const std::vector<MeterFaceBox>& faces) {
    auto r=relative_face_meter_candidate(raw,width,height,balanced_ev,{});
    if (!r.valid) return r;
    const double h=std::max(r.highlight_excess,0.0);
    r.scene_reduction_ev=r.area_weight*std::min({6.0,h,h*h/2.0});
    r.scene_ev=balanced_ev-r.scene_reduction_ev;
    for (size_t i=0;i<faces.size();++i) {
        const auto& f=faces[i];
        if (!std::isfinite(f.x)||!std::isfinite(f.y)||!std::isfinite(f.w)||!std::isfinite(f.h)||
            !std::isfinite(f.confidence)||f.confidence<.6||f.w<=0||f.h<=0) continue;
        const double w=std::clamp(f.x+f.w,0.0,1.0)-std::clamp(f.x,0.0,1.0);
        const double h=std::clamp(f.y+f.h,0.0,1.0)-std::clamp(f.y,0.0,1.0);
        if (w*width>=16 && h*height>=16) r.eligible_faces.push_back(int(i));
    }
    r.face_applied=!r.eligible_faces.empty();
    r.reduction_ev=r.face_applied ? std::min(r.scene_reduction_ev,.25) : r.scene_reduction_ev;
    r.candidate_ev=balanced_ev-r.reduction_ev;
    return r;
}
} // namespace spk::research
