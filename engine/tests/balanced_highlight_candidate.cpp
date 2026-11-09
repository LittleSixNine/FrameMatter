// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#include "../tools/balanced_highlight_candidate.hpp"
#include <cassert>
#include <iostream>
#include <limits>

using spk::research::balanced_highlight_candidate;
int main() {
    const std::vector<double> dark(10000, 0.184 / 64.0);
    auto uniform = balanced_highlight_candidate(dark, 6.0);
    assert(uniform.valid && uniform.highlight_area == 0 && uniform.candidate_ev == 6.0);
    auto point = dark;
    std::fill(point.begin(), point.begin() + 40, 4.0);
    auto isolated = balanced_highlight_candidate(point, 6.0);
    assert(isolated.highlight_area <= 0.005 && isolated.candidate_ev == 6.0);
    auto broad = dark;
    std::fill(broad.begin(), broad.begin() + 1000, 1.0);
    auto low_lift = balanced_highlight_candidate(broad, 2.5);
    assert(low_lift.candidate_ev == 2.5);
    auto risk = balanced_highlight_candidate(broad, 6.0);
    assert(risk.highlight_area > 0.03 && risk.candidate_ev < 1.0);
    assert(risk.reduction_ev > 5.0 && risk.reduction_ev <= 6.0);
    auto huge = balanced_highlight_candidate(broad, 12.0);
    assert(huge.reduction_ev == 6.0);
    double previous = 0;
    for (int i = 0; i <= 1200; ++i) {
        double ev = i / 100.0;
        auto sample = balanced_highlight_candidate(broad, ev);
        assert(sample.candidate_ev <= ev && sample.candidate_ev >= ev - 6.0);
        assert(sample.reduction_ev + 1e-12 >= previous);
        previous = sample.reduction_ev;
    }
    for (double join : {3.0, 5.0}) {
        auto left = balanced_highlight_candidate(broad, join - 1e-6);
        auto right = balanced_highlight_candidate(broad, join + 1e-6);
        assert(std::abs(left.candidate_ev - right.candidate_ev) < 1e-4);
    }
    assert(!balanced_highlight_candidate({}, 6.0).valid);
    auto invalid = dark;
    invalid[0] = std::numeric_limits<double>::quiet_NaN();
    auto refused = balanced_highlight_candidate(invalid, 6.0);
    assert(!refused.valid && refused.candidate_ev == 6.0);
    assert(!balanced_highlight_candidate(dark, std::numeric_limits<double>::infinity()).valid);
    std::cout << "PASS: uniform dark, isolated lights, lift gate, highlight area gate, bounded reduction, smooth joins, invalid input\n";
}
