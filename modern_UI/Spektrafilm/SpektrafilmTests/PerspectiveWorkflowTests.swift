// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import ImageIO
import XCTest

@MainActor
final class PerspectiveWorkflowTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end=Date().addingTimeInterval(120)
        while !condition(),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        guard condition() else { XCTFail("workflow wait timed out"); throw NSError(domain:"PerspectiveWorkflow",code:1) }
    }
    func testRealRAWPreFilmCorrectionCropAndUnwarpedFilmCanvas() async throws {
        guard let raw=ProcessInfo.processInfo.environment["FRAMEMATTER_TEST_RAW"] else { throw XCTSkip("opt-in real RAW path required") }
        let root=FileManager.default.temporaryDirectory.appending(path:"perspective-raw-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let previous=Sidecar.storeDirectory;Sidecar.useStore(at:root.appending(path:"sidecars"))
        defer {Sidecar.useStore(at:previous);try? FileManager.default.removeItem(at:root)}
        let url=root.appending(path:"frame.ARW");try FileManager.default.copyItem(at:URL(fileURLWithPath:raw),to:url)
        var edit=Sidecar();edit.params.grainActive=false;edit.params.glareActive=false;edit.params.halationActive=false;edit.params.autoExposure=false;try edit.save(for:url)
        let defaults=try XCTUnwrap(UserDefaults(suiteName:"perspective-raw-\(UUID())"))
        let diag=Diagnostics(defaults:defaults);diag.memoryReserveMegabytes=0
        let session=Session(diagnostics:diag,diskCache:try DiskCacheStore(root:root.appending(path:"cache")),clipboardDefaults:defaults)
        session.open(urls:[url]);try await wait {session.decoded != nil};session.requestPrint();_ = await session.ensureDeveloped()
        try await wait {session.canvasIsSettled && session.renderer.showsFullRender}
        let size=try XCTUnwrap(session.decoded?.pixelSize),beforeID=session.serviceSessionIDForExport,decodeCount=session.decodeCount
        let originalTexture=try XCTUnwrap(session.renderer.fullRender)
        let original=SHA256.hash(data:originalTexture.rgba16Bytes())
        try session.applyAgentEdit(["decode":["perspective":["vertical":12,"horizontal":-8]]])
        try await wait {session.serviceSessionIDForExport != beforeID && session.canvasIsSettled && session.renderer.showsFullRender && session.renderer.fullRender !== originalTexture}
        XCTAssertGreaterThan(session.decodeCount,decodeCount);XCTAssertEqual(session.decoded?.pixelSize,size)
        XCTAssertEqual(session.decoded?.display.extent.size,session.decoded?.linear.extent.size)
        XCTAssertNotEqual(SHA256.hash(data:try XCTUnwrap(session.renderer.fullRender).rgba16Bytes()),original)
        let correction=session.decode.perspective
        session.undo();XCTAssertTrue(session.decode.perspective.isNeutral)
        session.redo();XCTAssertEqual(session.decode.perspective,correction)
        try await wait {session.canvasIsSettled && session.renderer.showsFullRender && session.decoded != nil}
        session.flushSave();XCTAssertEqual(Sidecar.load(for:url)?.decode.perspective,correction)
        var g=session.geometry;g.crop=CropRect(x:0.1,y:0.1,width:0.8,height:0.8);session.geometry=g
        var recipe=ExportRecipe();recipe.format = .tiff;recipe.colorSpace = .displayP3;recipe.tiffCompression = .none
        recipe.folder = .fixed(path:root.appending(path:"out").path);recipe.subfolder=""
        let context=NamingRule.Context(originalName:"corrected",filmStock:session.params.filmStock,printStock:session.params.printStock,pixelSize:size,counter:1,date:Date())
        let result=try await Exporter.export(session:session,recipe:recipe,context:context,sessionID:try XCTUnwrap(session.serviceSessionIDForExport))
        guard case .wrote(let files,_,_)=result else {return XCTFail("no corrected TIFF")}
        let file=try XCTUnwrap(files.first), source=try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let expected=g.outputSize(for:size)
        XCTAssertEqual(image.width,Int(expected.width));XCTAssertEqual(image.height,Int(expected.height))
        XCTAssertEqual(image.bitsPerComponent,16);XCTAssertEqual(image.colorSpace?.copyICCData() as Data?,ImageDecoder.displayP3.copyICCData() as Data?)
        print("PERSPECTIVE_RAW source=\(Int(size.width))x\(Int(size.height)) cropped_file=\(image.width)x\(image.height) decode_changed=true")
        let beforeEdge=session.renderer.live
        var params=session.params;params.filmEdge.active=true;params.dateBack.active=true;params.dateBack.customText="26 11 09"
        session.params=params
        try await wait {session.engineFraming != nil && session.renderer.live !== beforeEdge && !session.busy && !session.scheduler.pending}
        XCTAssertTrue(session.canvasGeometry.isIdentity,"film text/date/perforations must not be post-warped")
        XCTAssertEqual(session.decode.perspective,correction)
        let edge=try await Exporter.filePixels(session:session,recipe:recipe,sessionID:try XCTUnwrap(session.serviceSessionIDForExport))
        // The full film may exceed the live tier; the output must retain the engine film aspect.
        let live=try XCTUnwrap(session.renderer.live)
        XCTAssertEqual(Double(edge.pixels.w)/Double(edge.pixels.h),Double(live.width)/Double(live.height),accuracy:0.003)
        if let directory=ProcessInfo.processInfo.environment["FRAMEMATTER_EVIDENCE_DIR"] {
            let out=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            let saved=out.appending(path:"corrected-crop.tif")
            try? FileManager.default.removeItem(at:saved)
            try FileManager.default.copyItem(at:file,to:saved)
            try Exporter.write(try XCTUnwrap(edge.texture.makeCGImage(space:edge.target)),to:out.appending(path:"corrected-film.tif"),format:.tiff,tiffCompression:.none)
        }
        print("PERSPECTIVE_FILM full=\(edge.pixels.w)x\(edge.pixels.h) post_geometry_identity=true date_and_edge_enabled=true")
        let edgeSID=session.serviceSessionIDForExport
        var neutralDecode=session.decode;neutralDecode.perspective=RawPerspective();session.decode=neutralDecode
        try await wait {session.serviceSessionIDForExport != edgeSID && session.serviceSessionIDForExport != nil && !session.busy && !session.scheduler.pending}
        let neutralEdge=try await Exporter.filePixels(session:session,recipe:recipe,sessionID:try XCTUnwrap(session.serviceSessionIDForExport))
        XCTAssertEqual(edge.pixels.w,neutralEdge.pixels.w);XCTAssertEqual(edge.pixels.h,neutralEdge.pixels.h)
        let width=2048,height=Int((Double(width)*Double(edge.pixels.h)/Double(edge.pixels.w)).rounded())
        let correctedSmall=try XCTUnwrap(session.renderer.applyResize(edge.texture,width:width,height:height))
        let neutralSmall=try XCTUnwrap(session.renderer.applyResize(neutralEdge.texture,width:width,height:height))
        let correctedBytes=correctedSmall.rgba16Bytes(),neutralBytes=neutralSmall.rgba16Bytes()
        var evidence:[String:Any]=[:]
        try correctedBytes.withUnsafeBytes { a in try neutralBytes.withUnsafeBytes { b in
            let aa=a.bindMemory(to:UInt16.self),bb=b.bindMemory(to:UInt16.self)
            func textBounds(_ p:UnsafeBufferPointer<UInt16>) -> [Int] {
                var minX=width,minY=height,maxX = -1,maxY = -1
                for y in 0..<(height*5/100) {for x in (width*8/100)..<(width*72/100) {
                    let offset=(y*width+x)*4
                    let red=Int(p[offset]),green=Int(p[offset+1]),blue=Int(p[offset+2])
                    if red>16000 && red>green*3/2 && red>blue*2 {
                        minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                    }
                }}
                return [minX,minY,maxX,maxY]
            }
            let first=textBounds(aa),second=textBounds(bb)
            XCTAssertGreaterThan(first[2]-first[0],width/4,"factory text ROI was not found")
            XCTAssertTrue(zip(first,second).allSatisfy {abs($0-$1)<=1},"factory text anchors moved")
            evidence=["roi":"upper factory film lettering","width":width,"height":height,
                      "corrected_bounds":first,"neutral_bounds":second,"tolerance_px":1]
            var difference=0.0,count=0
            for y in stride(from:height/3,to:height*2/3,by:4) {for x in stride(from:width/4,to:width*3/4,by:4) {for c in 0..<3 {
                let offset=(y*width+x)*4+c;difference+=abs(Double(aa[offset])-Double(bb[offset]))/65535;count+=1
            }}}
            evidence["inner_mean_absolute_change"]=difference/Double(count)
            XCTAssertGreaterThan(difference/Double(count),0.001)
        }}
        if let directory=ProcessInfo.processInfo.environment["FRAMEMATTER_EVIDENCE_DIR"] {
            let out=URL(fileURLWithPath:directory)
            try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:out.appending(path:"film-text-anchors.json"))
            for (name,texture) in [("corrected",correctedSmall),("neutral",neutralSmall)] {
                try Exporter.write(try XCTUnwrap(texture.makeCGImage(space:edge.target)),to:out.appending(path:"film-\(name).png"),format:.png)
            }
        }
        print("PERSPECTIVE_ROI "+String(data:try JSONSerialization.data(withJSONObject:evidence,options:.sortedKeys),encoding:.utf8)!)
        var restored=session.decode;restored.perspective=correction;session.decode=restored;session.flushSave()
        var pair=HalfFramePair(folder:root.path)
        var hole=HalfFramePair.Hole(url:url);hole.decode=try XCTUnwrap(Sidecar.load(for:url)).decode
        pair.left=hole;pair.right=hole
        let pairURL=root.appending(path:"piece.spektrapair")
        try pair.save(to:pairURL)
        func pairHash() throws -> String {
            PairComposer.rendered.removeAll()
            let decoded=try PairComposer.decode(pairURL)
            let texture=try XCTUnwrap(ImageDecoder.makePreviewTexture(decoded,device:session.renderer.device,maxEdge:2048,storageMode:.shared))
            return SHA256.hash(data:texture.rgba16Bytes()).map {String(format:"%02x",$0)}.joined()
        }
        let carried=try pairHash()
        pair.left?.decode.perspective=RawPerspective();pair.right?.decode.perspective=RawPerspective()
        try pair.save(to:pairURL)
        XCTAssertEqual(try pairHash(),carried,"a saved perspective leaked into the pair")
        XCTAssertEqual(Sidecar.load(for:url)?.decode.perspective,correction,"pair composition erased the single edit")
        print("PERSPECTIVE_PAIR nonzero_vs_neutral_equal=true source_preserved=true cache_cleared_each_arm=true")

        session.open(urls:[url,root.appending(path:"other.tif")]);await session.client.stop()
    }
}
