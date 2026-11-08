// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Run with checkout resources or the Resources/Resources/engine of an actual app.
#include "blob.hpp"
#include "colour.hpp"
#include "cam16.hpp"
#include "cam16_bake.hpp"
#include "setup_cache.hpp"
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <cstdio>
#include <limits>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    namespace fs = std::filesystem;
    const fs::path resources = argv[1];
    spk::Blob blob; spk::Colour colour; std::string error;
    if (!blob.open((resources / "spektrafilm_constants.bin").string(), error) || !colour.init(blob, error)) {
        std::fprintf(stderr, "%s\n", error.c_str()); return 2;
    }
    const auto tmp = fs::temp_directory_path() / ("cam16-check-" + std::to_string(
        std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(tmp / "cam16");
    int failures = 0, cases = 0;
    const auto check = [&](bool ok, const std::string& message) {
        if (!ok) { ++failures; std::fprintf(stderr, "FAIL %s\n", message.c_str()); }
    };
    const char* spaces[] = {"ProPhoto RGB", "Display P3", "sRGB", "Adobe RGB (1998)", "ITU-R BT.2020", "ACEScg"};
    for (const auto* space : spaces) {
        spk::Cam16Setup serial;
        if (!spk::cam16_setup_for(colour, space, serial, error)) { check(false, error); continue; }
        auto qualifies = serial;
        check(spk::cam16_bake::read((resources / "cam16").c_str(), space, qualifies), std::string(space) + " bundled artifact must qualify");
        const auto good = spk::cam16_bake::path((resources / "cam16").c_str(), space);
        std::ifstream input(good, std::ios::binary);
        const std::string bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
        if (bytes.empty()) { check(false, "missing known artifact"); continue; }
        for (const char* state : {"valid", "missing", "old", "future", "corrupt", "truncated", "wrong_space", "nan", "out_of_range"}) {
            const auto file = spk::cam16_bake::path((tmp / "cam16").c_str(), space);
            fs::remove(file);
            if (std::strcmp(state, "missing") != 0) {
                auto data = bytes;
                if (std::strcmp(state, "old") == 0 || std::strcmp(state, "future") == 0) {
                    const uint64_t revision = std::strcmp(state, "old") == 0 ? 0 : 999;
                    std::memcpy(data.data() + std::strlen("SPKCAM16BAKE"), &revision, sizeof revision);
                }
                if (std::strcmp(state, "corrupt") == 0) data.back() ^= 1;
                if (std::strcmp(state, "truncated") == 0) data.resize(128);
                if (std::strcmp(state, "wrong_space") == 0) data[std::strlen("SPKCAM16BAKE") + 16] ^= 1;
                if (std::strcmp(state, "nan") == 0 || std::strcmp(state, "out_of_range") == 0) {
                    const size_t payload_size = serial.c_max_table.size() * sizeof(double);
                    const size_t offset = data.size() - payload_size;
                    const double value = std::strcmp(state, "nan") == 0 ? std::numeric_limits<double>::quiet_NaN() : 151.0;
                    std::memcpy(data.data() + offset, &value, sizeof value);
                    const uint64_t checksum = spk::cam16_bake::hash(data.data() + offset, payload_size);
                    std::memcpy(data.data() + offset - sizeof checksum, &checksum, sizeof checksum);
                }
                std::ofstream output(file, std::ios::binary); output.write(data.data(), data.size());
            }
            auto probe = serial;
            const bool read = spk::cam16_bake::read((tmp / "cam16").c_str(), space, probe);
            check(read == (std::strcmp(state, "valid") == 0), std::string(space) + " " + state + " admission");
            // A fresh cache per case: a warm entry cannot hide a failed disk read.
            spk::SetupCache cache(tmp.string());
            const spk::Cam16Setup* actual = nullptr;
            const bool ok = cache.cam16(colour, space, actual, error);
            check(ok && actual && actual->c_max_table.size() == serial.c_max_table.size() &&
                std::memcmp(actual->c_max_table.data(), serial.c_max_table.data(), serial.c_max_table.size() * sizeof(double)) == 0,
                std::string(space) + " " + state + " all float64 cells");
            ++cases;
        }
        std::printf("checked %s: %zu doubles, 9 artifact states\n", space, serial.c_max_table.size());
    }
    spk::Cam16Setup unknown;
    check(!spk::cam16_setup_for(colour, "unknown colourspace", unknown, error), "unknown colourspace must retain its error");
    fs::remove_all(tmp);
    std::printf("%d cases, 0 skipped, %d failures\n", cases, failures);
    return failures ? 1 : 0;
}
