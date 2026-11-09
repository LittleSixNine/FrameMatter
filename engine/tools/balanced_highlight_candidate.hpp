// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

// Research v1 only. The ordinary engine does not include this header.
namespace spk::research {
struct BalancedHighlightCandidate {
    bool valid = false;
    double original_ev = 0;
    double candidate_ev = 0;
    double highlight_area = 0;
    double lift_weight = 0;
    double area_weight = 0;
    double p995_y = 0;
    double target_ev = 0;
    double reduction_ev = 0;
};

inline double smoothstep01(double t) {
    t = std::clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

inline BalancedHighlightCandidate balanced_highlight_candidate(
        const std::vector<double>& luminance, double balanced_ev) {
    constexpr double gray = 0.184;
    constexpr double floor = gray / 4096.0;
    BalancedHighlightCandidate result;
    result.original_ev = result.candidate_ev = balanced_ev;
    if (luminance.empty() || !std::isfinite(balanced_ev)) return result;
    std::vector<double> positive;
    positive.reserve(luminance.size());
    double area = 0;
    for (double y : luminance) {
        if (!std::isfinite(y)) return result;
        y = std::max(y, floor);
        positive.push_back(y);
        // A soft area count above gray +2.5..3 stops after balanced exposure.
        area += smoothstep01((std::log2(y / gray) + balanced_ev - 2.5) / 0.5);
    }
    result.valid = true;
    result.highlight_area = area / double(luminance.size());
    result.lift_weight = smoothstep01((balanced_ev - 3.0) / 2.0);
    result.area_weight = smoothstep01((result.highlight_area - 0.005) / 0.025);
    const size_t rank = (995u * (positive.size() - 1u)) / 1000u;
    std::nth_element(positive.begin(), positive.begin() + rank, positive.end());
    result.p995_y = positive[rank];
    result.target_ev = 2.5 - std::log2(result.p995_y / gray);
    result.reduction_ev = result.lift_weight * result.area_weight *
        std::clamp(balanced_ev - result.target_ev, 0.0, 6.0);
    result.candidate_ev = balanced_ev - result.reduction_ev;
    return result;
}
}  // namespace spk::research
