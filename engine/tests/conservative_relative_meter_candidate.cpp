// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#include "../tools/relative_face_meter_candidate.hpp"
#include <cassert>
#include <iostream>
using namespace spk::research;
int main() {
    for (double h:{0.,.5,1.,2.,4.,10.}) {
        std::vector<double> y(10000,.184*std::exp2(2.5+h));
        auto r=conservative_relative_meter_candidate(y,100,100,0,{});
        assert(r.valid && std::abs(r.reduction_ev-std::min({6.,h,h*h/2}))<1e-12);
        assert(r.reduction_ev<=std::min(h,6.) && r.candidate_ev<=r.original_ev);
        auto face=conservative_relative_meter_candidate(y,100,100,0,{{.2,.2,.4,.4,.9}});
        assert(face.face_applied && face.reduction_ev<=.25 && face.candidate_ev<=face.original_ev);
        auto ordered=conservative_relative_meter_candidate(y,100,100,0,{{.1,.1,.16,.16,.6},{.2,.2,.4,.4,.9}});
        auto reversed=conservative_relative_meter_candidate(y,100,100,0,{{.2,.2,.4,.4,.9},{.1,.1,.16,.16,.6}});
        assert(ordered.eligible_faces.size()==2 && reversed.eligible_faces.size()==2);
        assert(ordered.candidate_ev==reversed.candidate_ev && ordered.candidate_ev==face.candidate_ev);
        auto missing=conservative_relative_meter_candidate(y,100,100,0,{{.2,.2,.4,.4,.599},{.2,.2,.159,.4,.9}});
        assert(!missing.face_applied && missing.candidate_ev==r.candidate_ev);
        for (double gain:{.5,2.,4.}) {
            auto scaled=y;for(auto&v:scaled)v*=gain;
            auto f=std::vector<MeterFaceBox>{{.2,.2,.4,.4,.9}};
            auto a=conservative_relative_meter_candidate(y,100,100,0,f);
            auto b=conservative_relative_meter_candidate(scaled,100,100,-std::log2(gain),f);
            assert(std::abs(a.reduction_ev-b.reduction_ev)<1e-12);
            assert(std::abs(a.candidate_ev-std::log2(gain)-b.candidate_ev)<1e-12);
        }
    }
    std::vector<double> floored(10000,.184/8192);
    auto before=conservative_relative_meter_candidate(floored,100,100,16,{});
    for(auto&v:floored)v*=2;
    auto after=conservative_relative_meter_candidate(floored,100,100,15,{});
    assert(std::abs(before.reduction_ev-after.reduction_ev)>.1); // The documented floor exception.
    assert(!conservative_relative_meter_candidate({},100,100,0,{}).valid);
    std::cout<<"PASS v2.1 budgets, no lift, all-face/order invariance, missing faces, covariance/floor exception\n";
}
