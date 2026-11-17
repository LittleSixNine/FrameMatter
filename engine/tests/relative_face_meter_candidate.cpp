// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#include "../tools/relative_face_meter_candidate.hpp"
#include <cassert>
#include <iostream>
#include <limits>
using namespace spk::research;
int main() {
    std::vector<double> y(10000,.184/64);
    auto uniform=relative_face_meter_candidate(y,100,100,6,{});
    assert(uniform.valid && uniform.candidate_ev==6 && uniform.area==0);
    auto isolated=y;std::fill(isolated.begin(),isolated.begin()+40,4);
    assert(relative_face_meter_candidate(isolated,100,100,6,{}).candidate_ev==6);
    auto broad=y;std::fill(broad.begin(),broad.begin()+1000,1);
    auto scene=relative_face_meter_candidate(broad,100,100,6,{});
    assert(scene.reduction_ev==2 && scene.candidate_ev==4);
    auto face=relative_face_meter_candidate(broad,100,100,6,{{.2,.1,.4,.4,.6}});
    assert(face.face_applied && face.face_median_y==.184/64 && face.candidate_ev==6.5);
    auto capped=relative_face_meter_candidate(y,100,100,0,{{.2,.1,.4,.4,.6}});
    assert(capped.candidate_ev==1 && capped.face_target_ev>1);
    for (auto f:std::vector<MeterFaceBox>{{.2,.1,.4,.4,.599},{.2,.1,.159,.4,1}})
        assert(!relative_face_meter_candidate(y,100,100,6,{f}).face_applied);
    assert(relative_face_meter_candidate(y,100,100,6,{{0,0,.16,.16,.6}}).face_applied);
    // A bottom-left Vision box must read the bottom, not the bright top.
    auto asymmetric=y;std::fill(asymmetric.begin(),asymmetric.begin()+5000,.184*4);
    auto mapped=relative_face_meter_candidate(asymmetric,100,100,0,{{.2,.1,.4,.3,1}});
    assert(mapped.y0>=60 && mapped.y1<=90 && mapped.face_median_y==.184/64);
    std::vector<double> portrait(80*160,.184/64);std::fill(portrait.begin(),portrait.begin()+80*80,.184*4);
    auto vertical=relative_face_meter_candidate(portrait,80,160,0,{{.1,.1,.4,.3,1}});
    assert(vertical.y0>=96 && vertical.face_median_y==.184/64);
    auto tie=relative_face_meter_candidate(y,100,100,6,{{.5,.1,.2,.2,1},{.1,.1,.2,.2,1}});
    assert(tie.selected_face==1);
    for (double gain:{.5,2.0,4.0}) {
        auto scaled=broad;for(auto&v:scaled)v*=gain;
        auto a=relative_face_meter_candidate(broad,100,100,6,{{.2,.1,.4,.4,.9}});
        auto b=relative_face_meter_candidate(scaled,100,100,6-std::log2(gain),{{.2,.1,.4,.4,.9}});
        assert(std::abs(a.reduction_ev-b.reduction_ev)<1e-12);
        assert(std::abs(a.candidate_ev-std::log2(gain)-b.candidate_ev)<1e-12);
    }
    assert(!relative_face_meter_candidate({},100,100,6,{}).valid);
    y[0]=std::numeric_limits<double>::quiet_NaN();assert(!relative_face_meter_candidate(y,100,100,6,{}).valid);
    assert(!relative_face_meter_candidate(broad,100,100,std::numeric_limits<double>::infinity(),{}).valid);
    std::cout<<"PASS relative scene/face candidate, bounds, confidence/size, primary face, y mapping, covariance, invalid input\n";
}
