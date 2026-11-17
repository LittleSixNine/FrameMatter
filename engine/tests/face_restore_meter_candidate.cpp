// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#include "../tools/relative_face_meter_candidate.hpp"
#include <cassert>
#include <iostream>
using namespace spk::research;
int main() {
    for (double value:{.184/64,.184/4,.184,1.,4.}) for (double eb:{0.,1.,3.,6.}) {
        std::vector<double> y(10000,value);
        std::fill(y.begin(),y.begin()+1000,4.);
        for (const auto& faces:std::vector<std::vector<MeterFaceBox>>{{},{{.2,.1,.4,.4,.9}},{{.2,.1,.4,.4,.599}},{{.2,.1,.159,.4,.9}}}) {
            auto old=relative_face_meter_candidate(y,100,100,eb,faces);
            auto r=face_restored_relative_meter_candidate(y,100,100,eb,faces);
            assert(r.valid && r.before_restore_ev==old.candidate_ev);
            const double expected=old.face_applied ? std::min(.5,std::max(0.,eb-old.candidate_ev)) : 0;
            assert(r.face_restore_ev==expected && r.candidate_ev==old.candidate_ev+expected);
            assert(r.candidate_ev>=old.candidate_ev && r.face_restore_ev<=.5);
            if (old.candidate_ev<eb) assert(r.candidate_ev<=eb);
            else assert(r.candidate_ev==old.candidate_ev);
            if (!old.face_applied) assert(r.candidate_ev==old.candidate_ev);
            assert(r.selected_face==old.selected_face && r.face_median_y==old.face_median_y);
            assert(r.face_target_ev==old.face_target_ev && r.scene_ev==old.scene_ev);
        }
    }
    assert(!face_restored_relative_meter_candidate({},100,100,0,{}).valid);
    std::cout<<"PASS v2.2 restore cap/toward-balanced, no lowering, old lift/noface/qualification/selection unchanged\n";
}
