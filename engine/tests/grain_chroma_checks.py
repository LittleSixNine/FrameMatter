# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later

"""Check the product grain look through the native renderer (Metal)."""
import argparse

import numpy as np

from spk_ctypes import Engine
from spk_test_paths import add_engine_arguments, engine_options


def fluctuations(pixels):
    rgb = pixels[64:-64, 64:-64, :3].astype(np.float64) / 65535.0
    y = rgb @ np.array([0.2126729, 0.7151522, 0.0721750])
    # Measure colour fluctuations after removing variations along the patch's
    # average RGB proportions, so brightness alone contributes no colour.
    colour = rgb - y[..., None] * (rgb.mean(axis=(0, 1)) / y.mean())
    return np.array([y.std(), np.sqrt(colour.var(axis=(0, 1)).sum())])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_engine_arguments(parser)
    args = parser.parse_args()
    frame = np.empty((768, 1152, 3), dtype=np.float32)
    frame[:, :576] = 0.18
    frame[:, 576:] = [0.10, 0.22, 0.50]
    # The direct scan bypasses print-exposure compensation, the other
    # product-default difference. That makes the reference a clean control.
    settings = dict(scan_film=True, grain_active=True, grain_amount=2.0,
                    auto_exposure=False, halation_active=False, glare_active=False,
                    input_color_space="sRGB", output_color_space="sRGB",
                    input_cctf_decoding=False, output_cctf_encoding=False)
    with Engine(**engine_options(args)) as engine:
        with engine.open(frame, settings) as session:
            reference, _ = session.render("full")
            session.set_params({"grain_active": False})
            no_grain, _ = session.render("full")

        with engine.open(frame, settings | {"product_defaults": True}) as session:
            product, _ = session.render("full")
            session.set_params({"striped": True, "strip_rows": 113})
            cached, result = session.render("full", reprint=True)
            assert result.negative_was_cached and np.array_equal(product, cached)
            session.set_params({"grain_amount": 0.0})
            zero, _ = session.render("full")
            assert np.array_equal(no_grain, zero)

    for name, region in (("neutral", slice(0, 576)), ("blue", slice(576, 1152))):
        brightness, colour = fluctuations(product[:, region]) / fluctuations(reference[:, region])
        assert 0.94 < brightness < 1.06, (name, brightness)
        assert 0.26 < colour < 0.35, (name, colour)
        print(f"{name}: luminance RMS {brightness:.3f}, colour RMS {colour:.3f} vs reference")
    print("PASS grain chroma, zero strength and striped cached reprint")


if __name__ == "__main__":
    main()
