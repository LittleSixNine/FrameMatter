// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Recompute with FrameMatter's serial mathematics; never load an existing artifact.
#include "blob.hpp"
#include "colour.hpp"
#include "cam16.hpp"
#include "cam16_bake.hpp"
#include <filesystem>
#include <cstdio>
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    spk::Blob blob; spk::Colour colour; std::string error;
    if (!blob.open(std::string(argv[1]) + "/spektrafilm_constants.bin", error) || !colour.init(blob, error)) {
        std::fprintf(stderr, "%s\n", error.c_str()); return 1;
    }
    std::filesystem::create_directories(argv[2]);
    for (const char* space : {"ProPhoto RGB", "Display P3", "sRGB", "Adobe RGB (1998)", "ITU-R BT.2020", "ACEScg"}) {
        spk::Cam16Setup setup;
        if (!spk::cam16_setup_for(colour, space, setup, error) ||
            !spk::cam16_bake::write(argv[2], space, setup)) {
            std::fprintf(stderr, "cannot bake %s: %s\n", space, error.c_str()); return 1;
        }
        std::printf("baked %s: %zu doubles\n", space, setup.c_max_table.size());
    }
}
