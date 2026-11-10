// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "params.hpp"

namespace spk::meter {
struct FaceBox {
    double x=0, y=0, width=0, height=0, confidence=0;
};
struct AdaptiveResult {
    bool valid=false, face_measured=false;
    double balanced_ev=0, scene_ev=0, before_restore_ev=0, exposure_ev=0;
    double highlight_area=0, area_weight=0, p995_y=0, highlight_excess_ev=0, scene_reduction_ev=0;
    double face_median_y=0, face_target_ev=0, face_bound_ev=0, face_restore_ev=0;
    int selected_face=-1;
    uint32_t x0=0, y0=0, x1=0, y1=0;
};
// Invert node_geometry's output-centre mapping in continuous pixel-edge coordinates.
// A rotated box becomes an axis-aligned enclosure, clipped to the framed plane.
inline std::vector<FaceBox> framed_faces(const std::vector<FaceBox>& faces, uint32_t width,
                                        uint32_t height, const GeometryParams& geometry) {
    if (geometry.is_identity()) return faces;
    const auto& g=geometry;
    const uint32_t turns=uint32_t(((g.quarter_turns%4)+4)%4);
    const double cw=std::max(std::lround(g.crop_w*width),1L);
    const double ch=std::max(std::lround(g.crop_h*height),1L);
    const double ow=turns%2 ? ch : cw, oh=turns%2 ? cw : ch;
    const double angle=g.rotation_deg*3.14159265358979323846/180.0;
    const double ca=std::cos(angle), sa=std::sin(angle);
    std::vector<FaceBox> mapped;
    mapped.reserve(faces.size());
    for (const auto& face:faces) {
        double left=1, right=0, bottom=1, top=0;
        for (double x:{face.x,face.x+face.width}) for (double y:{face.y,face.y+face.height}) {
            const double dx=(x-g.crop_x-g.crop_w/2)*width;
            const double dy=(1-y-g.crop_y-g.crop_h/2)*height;
            const double u=(ca*dx+sa*dy+g.crop_w*width/2)/(g.crop_w*width/cw);
            const double v=(-sa*dx+ca*dy+g.crop_h*height/2)/(g.crop_h*height/ch);
            double ox=u, oy=v;
            if (turns==1) { ox=ow-v; oy=u; }
            else if (turns==2) { ox=ow-u; oy=oh-v; }
            else if (turns==3) { ox=v; oy=oh-u; }
            if (g.flip_h) ox=ow-ox;
            if (g.flip_v) oy=oh-oy;
            ox=std::clamp(ox/ow,0.0,1.0);
            oy=std::clamp(1-oy/oh,0.0,1.0);
            left=std::min(left,ox); right=std::max(right,ox);
            bottom=std::min(bottom,oy); top=std::max(top,oy);
        }
        mapped.push_back({left,bottom,right-left,top-bottom,face.confidence});
    }
    return mapped;
}

inline double smoothstep(double t) {
    t=std::clamp(t,0.0,1.0);
    return t*t*(3-2*t);
}

// Scene placement only; the profiles and the caller's RAW interpretation are independent.
inline AdaptiveResult adaptive_exposure(const std::vector<double>& raw, uint32_t width,
                                        uint32_t height, double balanced_ev,
                                        const std::vector<FaceBox>& faces) {
    AdaptiveResult r;
    r.balanced_ev=r.scene_ev=r.before_restore_ev=r.exposure_ev=balanced_ev;
    if (!width || !height || raw.size()!=size_t(width)*height || !std::isfinite(balanced_ev)) return r;
    constexpr double gray=.184, floor=gray/4096;
    std::vector<double> y;
    y.reserve(raw.size());
    for (double v:raw) {
        if (!std::isfinite(v)) return r;
        v=std::max(v,floor);
        y.push_back(v);
        r.highlight_area+=smoothstep((std::log2(v/gray)+balanced_ev-2.5)/.5);
    }
    r.highlight_area/=double(y.size());
    r.area_weight=smoothstep((r.highlight_area-.005)/.025);
    auto sorted=y;
    const size_t rank=995u*(sorted.size()-1u)/1000u;
    std::nth_element(sorted.begin(),sorted.begin()+rank,sorted.end());
    r.p995_y=sorted[rank];
    r.highlight_excess_ev=std::log2(r.p995_y/gray)+balanced_ev-2.5;
    r.scene_reduction_ev=r.area_weight*std::clamp(r.highlight_excess_ev,0.0,2.0);
    r.scene_ev=r.before_restore_ev=r.exposure_ev=balanced_ev-r.scene_reduction_ev;
    FaceBox selected;
    for (size_t i=0;i<faces.size();++i) {
        auto f=faces[i];
        if (!std::isfinite(f.x)||!std::isfinite(f.y)||!std::isfinite(f.width)||!std::isfinite(f.height)||
            !std::isfinite(f.confidence)||f.confidence<.6||f.width<=0||f.height<=0) continue;
        const double right=std::clamp(f.x+f.width,0.0,1.0), top=std::clamp(f.y+f.height,0.0,1.0);
        f.x=std::clamp(f.x,0.0,1.0);
        f.y=std::clamp(f.y,0.0,1.0);
        f.width=right-f.x;
        f.height=top-f.y;
        if (f.width*width<16 || f.height*height<16) continue;
        const double area=f.width*f.height, previous=selected.width*selected.height;
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
        r.x0=bound(selected.x+.2*selected.width,width);
        r.x1=bound(selected.x+.8*selected.width,width);
        r.y0=bound(1-selected.y-.8*selected.height,height);
        r.y1=bound(1-selected.y-.2*selected.height,height);
        std::vector<double> sample;
        for (uint32_t row=r.y0;row<r.y1;++row)
            for (uint32_t col=r.x0;col<r.x1;++col) sample.push_back(y[size_t(row)*width+col]);
        if (!sample.empty()) {
            const size_t middle=(sample.size()-1u)/2u;
            std::nth_element(sample.begin(),sample.begin()+middle,sample.end());
            r.face_median_y=sample[middle];
            r.face_target_ev=std::log2(gray*std::sqrt(2.0)/r.face_median_y);
            r.face_bound_ev=std::min(r.face_target_ev,balanced_ev+1.0);
            r.before_restore_ev=std::max(r.scene_ev,r.face_bound_ev);
            r.face_restore_ev=std::min(.5,std::max(0.0,balanced_ev-r.before_restore_ev));
            r.exposure_ev=r.before_restore_ev+r.face_restore_ev;
            r.face_measured=true;
        }
    }
    r.valid=true;
    return r;
}
} // namespace spk::meter
