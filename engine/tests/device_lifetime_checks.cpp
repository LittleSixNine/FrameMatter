// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Build: engine/build.sh tests; run: engine/build/device_lifetime_checks engine/resources
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <cstdio>
#include <memory>
#include <string>
#include "gpu/gpu.hpp"
#include "spektrafilm/spk_engine.h"

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    auto* pool = NS::AutoreleasePool::alloc()->init();
    auto* device = MTL::CreateSystemDefaultDevice();
    if (!device) { std::fprintf(stderr, "Metal device required\n"); return 2; }
    const std::string resources = argv[1];
    const auto make_and_destroy = [&](void* borrowed) {
        auto* inner = NS::AutoreleasePool::alloc()->init();
        auto* engine = spk_engine_create(resources.c_str(), borrowed);
        if (!engine) { std::fprintf(stderr, "%s\n", spk_last_error(nullptr)); std::exit(2); }
        spk_engine_destroy(engine);
        inner->release();
    };
    for (int i = 0; i < 4; ++i) make_and_destroy(device);
    const auto before = device->retainCount();
    for (int i = 0; i < 32; ++i) make_and_destroy(device);
    const auto after = device->retainCount();
    bool ok = before == after;
    std::printf("borrowed device: warmup=4 cycles=32 before=%lu after=%lu delta=%ld\n",
                before, after, long(after) - long(before));
    // The failed library path has already retained the caller's device.
    std::string error;
    auto* failure_pool = NS::AutoreleasePool::alloc()->init();
    auto* failed = spk::gpu::Gpu::create_metal(device, "/nonexistent/framematter.metallib", error);
    const bool refused = !failed;
    delete failed;
    failure_pool->release();
    const bool failure_ok = refused && device->retainCount() == after;
    std::printf("failed creation: before=%lu after=%lu %s\n", after, device->retainCount(), failure_ok ? "PASS" : "FAIL");
    ok = ok && failure_ok;
    for (int i = 0; i < 4; ++i) make_and_destroy(nullptr);
    // Destruction must leave the caller's device and its buffer ownership intact.
    auto* borrow_pool = NS::AutoreleasePool::alloc()->init();
    auto* buffer = device->newBuffer(64, MTL::ResourceStorageModeShared);
    if (!buffer) return 2;
    const auto buffer_before = buffer->retainCount();
    {
        std::unique_ptr<spk::gpu::Gpu> gpu(spk::gpu::Gpu::create_metal(
            device, resources + "/spektrafilm.metallib", error));
        if (!gpu) { std::fprintf(stderr, "%s\n", error.c_str()); return 2; }
        { auto borrowed = gpu->borrow(buffer, 64, error); ok = ok && bool(borrowed); }
        const auto stats = gpu->pool_stats();
        const bool buffer_ok = buffer->retainCount() == buffer_before && stats.audit.over_releases == 0;
        std::printf("borrowed buffer: before=%lu after=%lu over_releases=%llu %s\n",
                    buffer_before, buffer->retainCount(), stats.audit.over_releases, buffer_ok ? "PASS" : "FAIL");
        ok = ok && buffer_ok;
    }
    auto* queue = device->newCommandQueue();
    ok = ok && queue;
    if (queue) {
        auto* command = queue->commandBuffer();
        ok = ok && command;
        if (command) { command->commit(); command->waitUntilCompleted(); }
        queue->release();
    }
    buffer->release();
    borrow_pool->release();
    std::printf("caller device after all temporary owners: before=%lu after=%lu\n", after, device->retainCount());
    ok = ok && device->retainCount() == after;
    device->release();
    pool->release();
    std::printf("owned device / failed creation / caller queue / borrowed buffer: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
