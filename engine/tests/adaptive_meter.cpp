// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#include "../src/core/adaptive_meter.hpp"
#include <cassert>
#include <iostream>
#include <limits>
using namespace spk::meter;
int main() {
    std::vector<double> y(10000,.184/64);
    auto dark=adaptive_exposure(y,100,100,6,{});
    assert(dark.valid && dark.exposure_ev==6 && dark.highlight_area==0);
    auto tiny=y;std::fill(tiny.begin(),tiny.begin()+40,4);
    assert(adaptive_exposure(tiny,100,100,6,{}).exposure_ev==6);
    auto broad=y;std::fill(broad.begin(),broad.begin()+1000,1);
    auto scene=adaptive_exposure(broad,100,100,6,{});
    assert(scene.scene_reduction_ev==2 && scene.exposure_ev==4);
    auto lift=adaptive_exposure(broad,100,100,6,{{.2,.1,.4,.4,.6}});
    assert(lift.face_measured && lift.face_median_y==.184/64 && lift.exposure_ev==6.5 && lift.face_restore_ev==0);
    auto bright_face=broad;std::fill(bright_face.begin()+5000,bright_face.end(),.184/2);
    auto restore=adaptive_exposure(bright_face,100,100,6,{{.2,.1,.4,.3,.9}});
    assert(restore.face_measured && restore.before_restore_ev==4 && restore.face_restore_ev==.5 && restore.exposure_ev==4.5);
    for (const auto& box:std::vector<FaceBox>{{.2,.1,.4,.4,.599},{.2,.1,.159,.4,.9}})
        assert(!adaptive_exposure(y,100,100,6,{box}).face_measured);
    assert(adaptive_exposure(y,100,100,6,{{0,0,.16,.16,.6}}).face_measured);
    auto tied=adaptive_exposure(y,100,100,6,{{.5,.1,.2,.2,1},{.1,.1,.2,.2,1}});
    assert(tied.selected_face==1);
    for (double gain:{.5,2.,4.}) {
        auto scaled=bright_face;for(auto&v:scaled)v*=gain;
        auto f=std::vector<FaceBox>{{.2,.1,.4,.3,.9}};
        auto a=adaptive_exposure(bright_face,100,100,6,f);
        auto b=adaptive_exposure(scaled,100,100,6-std::log2(gain),f);
        assert(std::abs(a.exposure_ev-std::log2(gain)-b.exposure_ev)<1e-12);
    }
    const FaceBox source{.1,.2,.2,.3,.9};
    spk::GeometryParams geometry;
    auto equal=[](double a,double b) { return std::abs(a-b)<1e-12; };
    geometry.flip_h=true;
    auto f=framed_faces({source},100,100,geometry)[0];
    assert(equal(f.x,.7) && equal(f.y,.2) && equal(f.width,.2) && equal(f.height,.3));
    geometry={}; geometry.quarter_turns=1;
    f=framed_faces({source},100,100,geometry)[0];
    assert(equal(f.x,.2) && equal(f.y,.7) && equal(f.width,.3) && equal(f.height,.2));
    geometry={}; geometry.crop_x=.1;geometry.crop_y=.2;geometry.crop_w=.5;geometry.crop_h=.6;
    f=framed_faces({source},100,100,geometry)[0];
    assert(equal(f.x,0) && equal(f.y,0) && equal(f.width,.4) && equal(f.height,.5));
    assert(framed_faces({{.9,.9,.05,.05,.9}},100,100,geometry)[0].width==0);
    geometry={};geometry.crop_x=.2;geometry.crop_w=.4;
    f=framed_faces({source},100,100,geometry)[0];
    assert(equal(f.x,0) && equal(f.width,.25) && equal(f.height,.3));
    geometry={}; geometry.rotation_deg=45;
    f=framed_faces({{.4,.4,.2,.2,.9}},100,100,geometry)[0];
    assert(equal(f.width,std::sqrt(.08)) && equal(f.height,std::sqrt(.08)));
    f=framed_faces({{.5,.2,0,.5,.9}},100,100,geometry)[0];
    assert(f.width==0 && f.height==0); // A zero-area placeholder must not rotate into a face.
    assert(!adaptive_exposure({},100,100,6,{}).valid);
    y[0]=std::numeric_limits<double>::quiet_NaN();assert(!adaptive_exposure(y,100,100,6,{}).valid);
    std::cout<<"PASS adaptive frozen scene, face/lift/restore, eligibility, primary face, covariance, invalid input\n";
}
