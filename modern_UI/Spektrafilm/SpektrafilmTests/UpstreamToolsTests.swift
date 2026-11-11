// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Metal
import XCTest

@MainActor
final class UpstreamToolsTests: XCTestCase {
    private func pixels(_ colors: [[Float]], _ adjustments: Adjustments, maskCount: Int = 0) throws -> [UInt16] {
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(Renderer(device: gpu))
        renderer.masks = Array(repeating: MaskUniform(), count: maskCount)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
            width: colors.count, height: 1, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .shaderWrite]
        let input = try XCTUnwrap(gpu.makeTexture(descriptor: d))
        let data: [Float] = colors.flatMap { $0 + [1] }
        data.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, colors.count, 1), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: colors.count * 16) }
        let output = try XCTUnwrap(renderer.applyAdjustments(adjustments, to: input))
        var result = [UInt16](repeating: 0, count: colors.count * 4)
        output.getBytes(&result, bytesPerRow: colors.count * 8,
            from: MTLRegionMake2D(0, 0, colors.count, 1), mipmapLevel: 0)
        return result
    }


    func testMissingFieldsAreNeutralAndReadbackIsComplete() throws {
        var doc = try JSONValue.from(Sidecar()).object!
        var params = doc["params"]!.object!; params.removeValue(forKey:"sceneCurve");doc["params"] = .object(params)
        let old = try JSONValue.object(doc).decode(Sidecar.self)
        XCTAssertTrue(old.params.sceneCurve.isIdentity);XCTAssertEqual(old.adjustments.vibrance,0)
        XCTAssertTrue(old.adjustments.channelMixer.isNeutral)
        let readback = try AgentDocument(old).json
        XCTAssertEqual(readback["adjustments"]?["vibrance"],0)
        XCTAssertEqual(readback["adjustments"]?["channelMixer"]?["red"]?["red"],0)
        XCTAssertEqual(old.params.sceneCurve.sceneWire,"")
        let legacy = old.params.wire.filter {$0.name != "scene_curve" && $0.name != "overscan_factory_separate_halation"}.map {"\($0.name)=\($0.value)"}.joined(separator:";")
        XCTAssertEqual(Session.printStamp(old.params),legacy)
    }
    func testCurveShootDeltaClipboardAndAtomicPatch() throws {
        let before = AgentDocument(Sidecar())
        let patch: JSONValue = ["params":["sceneCurve":["luma":["points":[[0,0],[0.5,0.55],[1,1]]]]],"adjustments":["vibrance":40,"channelMixer":["red":["green":20]]]]
        let after=try before.merged(with:patch)
        XCTAssertEqual(after.params.delta(from:before.params).layers,[.shoot])
        XCTAssertFalse(after.params.sceneCurve.sceneWire.isEmpty)
        XCTAssertNotEqual(Session.printStamp(before.params),Session.printStamp(after.params))
        XCTAssertThrowsError(try AgentDocument.validate(["adjustments":["vibrance":40,"channelMixer":["blue":["red":101]]]]))
        XCTAssertThrowsError(try AgentDocument.validate(["params":["sceneCurve":["rgb":["points":[[0,0],[0.5,2],[1,1]]]]]]))
        var source=Sidecar();source.params=after.params;source.adjustments=after.adjustments
        let target=Sidecar()
        let pasted=SettingsClip(groups:[.scenePlacement,.postDev],settings:source,sourceName:"source").applied(to:target)
        XCTAssertEqual(pasted.params.sceneCurve,source.params.sceneCurve);XCTAssertEqual(pasted.adjustments,source.adjustments)
        XCTAssertEqual(try JSONDecoder().decode(Sidecar.self,from:JSONEncoder().encode(source)),source)
    }
    func testVibranceProtectsGreyAndSaturatedPrimaries() throws {
        let colors:[[Float]]=[[0.3,0.3,0.3],[1,0,0],[0,0,1],[0.7,0.5,0.4]]
        let before=try pixels(colors,Adjustments());var a=Adjustments();a.vibrance=70
        let after=try pixels(colors,a)
        XCTAssertEqual(Array(before.prefix(12)),Array(after.prefix(12)))
        XCTAssertNotEqual(Array(before.suffix(4)),Array(after.suffix(4)))
        a.enabled=false;XCTAssertEqual(try pixels(colors,a),before)
        let color:[Float]=[0.7,0.5,0.4]
        for amount in [-60.0,60.0] {
            var grade=Adjustments();grade.vibrance=amount
            let actual=try pixels([color],grade)
            let y:Float=0.2126*color[0]+0.7152*color[1]+0.0722*color[2]
            let sat:Float=(0.7-0.4)/0.7, gain=1+Float(amount/100)*(1-sat)
            for c in 0..<3 { XCTAssertEqual(Int(actual[c]),Int(((y+(color[c]-y)*gain)*65535).rounded()),accuracy:2) }
        }
    }
    func testMixerIsIdentityPlusPercentOffsetsAndBounded() throws {
        let colors:[[Float]]=[[0.6,0.2,0.1],[0.2,0.4,0.8]]
        var a=Adjustments();a.channelMixer.red.green=50
        let out=try pixels(colors,a)
        XCTAssertEqual(Int(out[0]),Int((Float(0.7)*65535).rounded()),accuracy:2)
        XCTAssertEqual(Int(out[1]),Int((Float(0.2)*65535).rounded()),accuracy:2)
        a.channelMixer.red.red = .infinity;a.channelMixer.blue.green=1000
        XCTAssertTrue(a.colorUniforms.mixR.x.isFinite)
        XCTAssertEqual(a.colorUniforms.mixB.y,1)
        XCTAssertEqual(MemoryLayout<Layer2Uniforms>.stride,224)
        XCTAssertEqual(MemoryLayout<HSLUniforms>.stride,192)
    }
    func testOffscreenExplicitGradeDoesNotInheritLiveColourAndRestoresIt() throws {
        let gpu=try XCTUnwrap(MTLCreateSystemDefaultDevice()),r=try XCTUnwrap(Renderer(device:gpu))
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:1,height:1,mipmapped:false)
        d.storageMode = .shared;d.usage=[.shaderRead,.shaderWrite]
        let input=try XCTUnwrap(gpu.makeTexture(descriptor:d));var data:[Float]=[0.6,0.2,0.1,1]
        data.withUnsafeBytes { input.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:16) }
        var live=Adjustments();live.vibrance=80;live.channelMixer.blue.red=70;r.hsl=live.colorUniforms
        _=try XCTUnwrap(r.applyAdjustments(Adjustments(),to:input))
        XCTAssertEqual(r.hsl.vibrance,live.colorUniforms.vibrance);XCTAssertEqual(r.hsl.mixB,live.colorUniforms.mixB)
        let neutral=try XCTUnwrap(r.applyAdjustments(Adjustments(),to:input)).rgba16Bytes()
        r.hsl=HSLUniforms()
        XCTAssertEqual(try XCTUnwrap(r.applyAdjustments(Adjustments(),to:input)).rgba16Bytes(),neutral)
        r.hsl=live.colorUniforms
        let decoded=try XCTUnwrap(r.applyCineonView(to:input)).rgba16Bytes()
        r.hsl=HSLUniforms();XCTAssertEqual(try XCTUnwrap(r.applyCineonView(to:input)).rgba16Bytes(),decoded)
    }
    /// Frozen source is an opt-in integration control, not a golden image regenerated by the new shader.
    func testFrozenOldShaderWithNewNeutralControls() throws {
        guard let path=ProcessInfo.processInfo.environment["FRAMEMATTER_OLD_LAYER2"] else { throw XCTSkip("frozen old shader source required") }
        let gpu=try XCTUnwrap(MTLCreateSystemDefaultDevice()),r=try XCTUnwrap(Renderer(device:gpu))
        let old=try gpu.makeLibrary(source:String(contentsOfFile:path,encoding:.utf8),options:nil)
        let current=try gpu.makeDefaultLibrary(bundle:Bundle(for:Renderer.self))
        let w=257,h=17
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:w,height:h,mipmapped:false)
        desc.storageMode = .shared;desc.usage=[.shaderRead,.shaderWrite]
        let src=try XCTUnwrap(gpu.makeTexture(descriptor:desc))
        let values:[Float]=(0..<(w*h)).flatMap { i in [Float(i%31)/20-0.1,Float(i%43)/32,Float(i%17)/15,1] }
        values.withUnsafeBytes {src.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:w*16)}
        let curves=try XCTUnwrap(r.store.makeCurveTable())
        let md=MTLTextureDescriptor();md.textureType = .type2DArray;md.pixelFormat = .r8Unorm;md.width=1;md.height=1;md.arrayLength=1;md.usage = .shaderRead
        let masks=try XCTUnwrap(gpu.makeTexture(descriptor:md))
        let ld=MTLTextureDescriptor();ld.textureType = .type3D;ld.pixelFormat = .rgba32Float;ld.width=2;ld.height=2;ld.depth=2;ld.usage = .shaderRead
        let lut=try XCTUnwrap(gpu.makeTexture(descriptor:ld))
        func run(_ library:MTLLibrary,_ grade:Adjustments) throws -> Data {
            let fn=try XCTUnwrap(library.makeFunction(name:"layer2")),pipeline=try gpu.makeComputePipelineState(function:fn)
            let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Unorm,width:w,height:h,mipmapped:false);dd.storageMode = .shared;dd.usage=[.shaderRead,.shaderWrite]
            let dst=try XCTUnwrap(gpu.makeTexture(descriptor:dd)),cb=try XCTUnwrap(r.queue.makeCommandBuffer()),e=try XCTUnwrap(cb.makeComputeCommandEncoder())
            r.store.upload(curves:grade.curves,into:curves)
            e.setComputePipelineState(pipeline);e.setTexture(src,index:0);e.setTexture(dst,index:1);e.setTexture(curves,index:2);e.setTexture(masks,index:3);e.setTexture(lut,index:4)
            var u=grade.uniforms,c=grade.colorUniforms,m=MaskUniform(),count:UInt32=0,overlay:Int32 = -1
            e.setBytes(&u,length:MemoryLayout<Layer2Uniforms>.stride,index:0);e.setBytes(&m,length:MemoryLayout<MaskUniform>.stride,index:1)
            e.setBytes(&count,length:4,index:2);e.setBytes(&overlay,length:4,index:3);e.setBytes(&c,length:MemoryLayout<HSLUniforms>.stride,index:4)
            e.dispatchThreads(MTLSize(width:w,height:h,depth:1),threadsPerThreadgroup:MTLSize(width:16,height:8,depth:1));e.endEncoding();cb.commit();cb.waitUntilCompleted()
            XCTAssertNil(cb.error)
            return dst.rgba16Bytes()
        }
        var grade=Adjustments();XCTAssertEqual(try run(old,grade),try run(current,grade))
        grade.exposure=0.7;grade.contrast=12;grade.colorBalance.shadows.saturation=0.2;grade.colorBalance.shadows.hue=35
        grade.hsl.orange.hue=12;grade.hsl.blue.saturation = -20;grade.vignette.amount = -20
        grade.curves.luma.points=[CGPoint(x:0,y:0),CGPoint(x:0.5,y:0.56),CGPoint(x:1,y:1)]
        XCTAssertEqual(try run(old,grade),try run(current,grade),"old non-neutral CB/HSL/curves must remain bit-exact")
        print("PASS frozen old/current Layer2 RGB16 exact: neutral and legacy non-neutral CB/HSL/curves")
    }

    func testHostOnlyFilmMetadataSettlesWithoutAnEngineCall() async throws {
        let scheduler=RenderScheduler(client:EngineClient(device:try XCTUnwrap(MTLCreateSystemDefaultDevice())))
        let original=FilmParams.default
        _=scheduler.reset(sessionID:"must-not-be-called",params:original)
        var target=original;target.dateBack.framing="crop-only-metadata";target.filmEdge.framing="dormant-edge"
        XCTAssertTrue(target.delta(from:original).delta.isEmpty)
        var busy=0,results=0,errors=0
        scheduler.onBusy={_ in busy += 1};scheduler.onResult={_,_,_ in results += 1};scheduler.onError={_ in errors += 1}
        scheduler.request(target)
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(scheduler.sent,target)
        XCTAssertFalse(scheduler.pending)
        XCTAssertEqual(busy,0);XCTAssertEqual(results,0);XCTAssertEqual(errors,0)
        scheduler.invalidate()
    }

}
