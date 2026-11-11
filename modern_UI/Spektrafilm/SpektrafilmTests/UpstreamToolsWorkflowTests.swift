// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import ImageIO
import XCTest

@MainActor
final class UpstreamToolsWorkflowTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(120)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition())
    }
    private func hash(_ image: CGImage) throws -> String {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 16, bytesPerRow: image.width * 8, space: image.colorSpace!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        context.draw(image, in: CGRect(x:0,y:0,width:image.width,height:image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt16.self)
        for i in stride(from:3,to:image.width*image.height*4,by:4) { pixels[i] = 0 }
        return SHA256.hash(data:Data(bytes:pixels,count:image.width*image.height*8)).map { String(format:"%02x",$0) }.joined()
    }
    func testRealRAWSceneCurveColourUndoSaveReopenPreviewAndProofTIFF() async throws {
        guard let raw = ProcessInfo.processInfo.environment["FRAMEMATTER_TEST_RAW"] else {
            throw XCTSkip("opt-in real RAW path required")
        }
        let root = ProcessInfo.processInfo.environment["FRAMEMATTER_QA_OUTPUT"].map { URL(fileURLWithPath:$0) }
            ?? FileManager.default.temporaryDirectory.appending(path:"three-tools-workflow-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let previous = Sidecar.storeDirectory; Sidecar.useStore(at:root.appending(path:"sidecars"))
        defer { Sidecar.useStore(at:previous); if ProcessInfo.processInfo.environment["FRAMEMATTER_QA_OUTPUT"] == nil { try? FileManager.default.removeItem(at:root) } }
        let url = root.appending(path:"frame.ARW")
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        try FileManager.default.copyItem(at:URL(fileURLWithPath:raw),to:url)
        var edit=Sidecar(); edit.params.grainActive=false; edit.params.glareActive=false
        try edit.save(for:url)
        let defaults=try XCTUnwrap(UserDefaults(suiteName:"three-tools-workflow-\(UUID())"))
        let diag=Diagnostics(defaults:defaults);diag.memoryReserveMegabytes=0
        let session=Session(diagnostics:diag,diskCache:try DiskCacheStore(root:root.appending(path:"cache")),clipboardDefaults:defaults)
        let ws = AgentWorkspace(session:session);ws.timeout=30;try await ws.open(url.path);_ = await session.ensureDeveloped()
        try await wait { session.canvasIsSettled && session.renderer.showsFullRender }
        let original=try XCTUnwrap(session.renderer.fullRender).rgba16Bytes()
        let beforeDecode = session.decodeCount
        try session.applyAgentEdit(["params":["sceneCurve":["luma":["points":[[0,0],[0.5,0.54],[1,1]]]]]])
        try await wait { session.canvasIsSettled && session.scheduler.sent == session.params && session.renderer.showsFullRender }
        XCTAssertNotEqual(try XCTUnwrap(session.renderer.fullRender).rgba16Bytes(),original)
        XCTAssertEqual(session.decodeCount,beforeDecode)
        let curve = session.params.sceneCurve
        session.undo();XCTAssertTrue(session.params.sceneCurve.isIdentity)
        session.redo();XCTAssertEqual(session.params.sceneCurve,curve)
        try await wait { session.canvasIsSettled && session.scheduler.sent == session.params && session.renderer.showsFullRender }
        let afterScene = try XCTUnwrap(session.renderer.fullRender).rgba16Bytes()
        let decodes=session.decodeCount
        let beforeRenderCount=session.log.records().filter { $0.message == "render" }.count
        try session.applyAgentEdit(["adjustments":["vibrance":45,"channelMixer":["red":["green":20]],"hsl":["orange":["hue":12,"saturation":25],"blue":["lightness":-15]]]])
        let adjusted=session.adjustments
        XCTAssertThrowsError(try session.applyAgentEdit(["adjustments":["exposure":1,"hsl":["red":["hue":31]]]]))
        XCTAssertEqual(session.adjustments,adjusted)
        try await Task.sleep(for:.milliseconds(600))
        XCTAssertEqual(session.log.records().filter { $0.message == "render" }.count,beforeRenderCount)
        XCTAssertEqual(session.decodeCount,decodes)
        XCTAssertEqual(try XCTUnwrap(session.renderer.fullRender).rgba16Bytes(),afterScene)
        session.undo();XCTAssertTrue(session.adjustments.hsl.isNeutral);XCTAssertTrue(session.canRedo)
        session.redo();XCTAssertEqual(session.adjustments,adjusted)
        XCTAssertEqual(session.log.records().filter { $0.message == "render" }.count,beforeRenderCount)
        session.flushSave();XCTAssertEqual(Sidecar.load(for:url)?.adjustments,adjusted)
        XCTAssertFalse(session.clipboardGroups.contains(.postDev))
        session.clipboardGroups=[.postDev];session.copySettings()
        session.adjustments=Adjustments();session.pasteSettings()
        XCTAssertEqual(session.adjustments,adjusted)
        XCTAssertEqual(session.renderer.hsl.active,1)
        XCTAssertEqual(session.renderer.hsl.mixerActive,1)
        session.geometry.crop = CropRect(x:0.1,y:0.15,width:0.6,height:0.7)
        session.geometry.quarterTurns = 1
        let preview = try await ws.preview(to:root.appending(path:"agent-preview.jpg"),longEdge:512)
        let previewSource=try XCTUnwrap(CGImageSourceCreateWithURL(preview as CFURL,nil))
        let previewImage=try XCTUnwrap(CGImageSourceCreateImageAtIndex(previewSource,0,nil))
        let logical=session.renderer.logicalSize(forSource:session.sourceImageSize)
        XCTAssertEqual(Double(previewImage.width)/Double(previewImage.height),logical.width/logical.height,accuracy:0.01)
        XCTAssertEqual(session.log.records().filter {$0.message == "render"}.count,beforeRenderCount,"downstream geometry acknowledgement must not render the film")
        XCTAssertEqual(session.decodeCount,decodes)

        let store=ExportRecipeStore(url:root.appending(path:"recipes.json"))
        var recipe=try XCTUnwrap(store.selected);recipe.name="Three tools proof";recipe.format = .tiff
        recipe.tiffCompression = .none;recipe.colorSpace = .displayP3
        recipe.folder = .fixed(path:root.appending(path:"out").path);recipe.subfolder="";store.selected=recipe
        recipe=try XCTUnwrap(ExportRecipeStore(url:store.url).selected)
        XCTAssertEqual(recipe.name,"Three tools proof");XCTAssertEqual(recipe.tiffCompression,TIFFCompression.none)
        let madeProof = await session.softProof(recipe:recipe)
        let proof = try XCTUnwrap(madeProof)
        let context=NamingRule.Context(originalName:"frame",filmStock:session.params.filmStock,printStock:session.params.printStock,
            pixelSize:try XCTUnwrap(session.decoded?.pixelSize),counter:1,date:Date())
        let result=try await Exporter.export(session:session,recipe:recipe,context:context,sessionID:try XCTUnwrap(session.serviceSessionIDForExport))
        guard case .wrote(let files,_,_) = result else { return XCTFail("export failed") }
        let output=try XCTUnwrap(files.first), source=try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(Double(image.width)/Double(image.height),logical.width/logical.height,accuracy:0.001)
        XCTAssertEqual(image.bitsPerComponent,16)
        XCTAssertEqual(image.colorSpace?.copyICCData() as Data?,proof.target.copyICCData() as Data?)
        XCTAssertEqual(try hash(image),try hash(proof.image))
        let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
        XCTAssertEqual((props[kCGImagePropertyTIFFDictionary] as? [String:Any])?["Compression"] as? Int,1)
        session.flushSave()
        XCTAssertEqual(Sidecar.load(for:url)?.params.sceneCurve,curve)
        session.open(urls:[root.appending(path:"other.tif")]);session.open(urls:[url])
        try await wait { session.decoded != nil && session.params.sceneCurve == curve }
        XCTAssertEqual(session.adjustments,adjusted)
        print("THREE_TOOLS_WORKFLOW dimensions=\(image.width)x\(image.height) proof_file_rgb16_hash=\(try hash(image)) grade_extra_renders=0 extra_decodes=0")
        session.open(urls:[url,root.appending(path:"other.tif")]);await session.client.stop()
    }
}
