// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
import CoreImage
import XCTest

@MainActor
final class PerspectiveTests: XCTestCase {
    func testIdentityCornersAndInverseAcrossBothAxes() {
        let size=CGSize(width:6000,height:4000)
        XCTAssertTrue(RawPerspective().map(in:size).isIdentity)
        for v in [-30.0,-10,0,10,30] { for h in [-30.0,-10,0,10,30] {
            let map=RawPerspective(vertical:v,horizontal:h).map(in:size)
            for point in [CGPoint(x:0,y:0),CGPoint(x:6000,y:0),CGPoint(x:6000,y:4000),CGPoint(x:0,y:4000),CGPoint(x:3000,y:2000)] {
                let source=map.source(point), back=map.corrected(source)
                XCTAssertGreaterThanOrEqual(source.x,-0.0001);XCTAssertLessThanOrEqual(source.x,6000.0001)
                XCTAssertGreaterThanOrEqual(source.y,-0.0001);XCTAssertLessThanOrEqual(source.y,4000.0001)
                XCTAssertEqual(back.x,point.x,accuracy:1e-7);XCTAssertEqual(back.y,point.y,accuracy:1e-7)
            }
            XCTAssertEqual(map.corrected(CGPoint(x:3000,y:2000)).x,3000,accuracy:1e-7)
            XCTAssertEqual(map.corrected(CGPoint(x:3000,y:2000)).y,2000,accuracy:1e-7)
        } }
    }

    func testCoreImageProjectionMatchesTheCoordinateMapAndKeepsTheFrame() throws {
        let w=96,h=64
        let pixels:[Float]=(0..<h).flatMap { y in (0..<w).flatMap { x in [Float(x)/Float(w),Float(y)/Float(h),Float(0.4),Float(1)] } }
        let image=CIImage(bitmapData:pixels.withUnsafeBytes { Data($0) },bytesPerRow:w*16,size:CGSize(width:w,height:h),format:.RGBAf,colorSpace:ImageDecoder.linearProPhoto)
        XCTAssertTrue(try RawPerspective().applying(to:image) === image)
        let perspective=RawPerspective(vertical:18,horizontal:-12)
        let corrected=try perspective.applying(to:image)
        XCTAssertEqual(corrected.extent,image.extent)
        let context=CIContext(options:[.workingColorSpace:ImageDecoder.linearProPhoto])
        var output=[Float](repeating:0,count:w*h*4)
        context.render(corrected,toBitmap:&output,rowBytes:w*16,bounds:image.extent,format:.RGBAf,colorSpace:ImageDecoder.linearProPhoto)
        let map=perspective.map(in:image.extent.size)
        for (x,y) in [(4,4),(w-5,4),(w-5,h-5),(4,h-5),(w/2,h/2)] {
            // Bitmap rows and the coordinate target both use a top-left origin.
            let source=map.source(CGPoint(x:Double(x)+0.5,y:Double(y)+0.5))
            XCTAssertEqual(Double(output[(y*w+x)*4]),(source.x-0.5)/Double(w),accuracy:0.025)
            XCTAssertEqual(Double(output[(y*w+x)*4+1]),(source.y-0.5)/Double(h),accuracy:0.025)
            XCTAssertEqual(output[(y*w+x)*4+3],1,accuracy:0.001)
        }
    }

    func testOldDecodeRoundtripAndCacheInvalidation() throws {
        var settings=DecodeSettings()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
        json.removeValue(forKey:"perspective")
        XCTAssertEqual(try JSONDecoder().decode(DecodeSettings.self,from:JSONSerialization.data(withJSONObject:json)),settings)
        let url=URL(fileURLWithPath:"/tmp/perspective.ARW")
        let oldDecode=Session.displayCacheKey(url:url,settings:settings,previewLongEdge:2560,engineVersion:"test")
        let oldPrint=Session.printCacheKey(url:url,params:FilmParams(),settings:settings,tier:.full,previewLongEdge:2560,engineVersion:"test")
        settings.perspective=RawPerspective(vertical:12,horizontal:-7)
        XCTAssertEqual(try JSONDecoder().decode(DecodeSettings.self,from:JSONEncoder().encode(settings)),settings)
        XCTAssertNotEqual(oldDecode,Session.displayCacheKey(url:url,settings:settings,previewLongEdge:2560,engineVersion:"test"))
        XCTAssertNotEqual(oldPrint,Session.printCacheKey(url:url,params:FilmParams(),settings:settings,tier:.full,previewLongEdge:2560,engineVersion:"test"))
        XCTAssertNotEqual(DecodeKey(url:url,settings:DecodeSettings()),DecodeKey(url:url,settings:settings))
    }

    func testOptionalCopyAndSchemaValidation() throws {
        var source=Sidecar();source.decode.perspective=RawPerspective(vertical:10,horizontal:-5)
        let target=Sidecar(), clip=SettingsClip(groups:[.perspective],settings:source,sourceName:"source")
        XCTAssertEqual(clip.applied(to:target).decode.perspective,source.decode.perspective)
        XCTAssertEqual(clip.applied(to:target,perspectiveAllowed:false),target)
        XCTAssertEqual(SettingsClip(groups:[.whiteBalance],settings:source,sourceName:"source").applied(to:target),target)
        XCTAssertThrowsError(try AgentDocument.validate(["decode":["perspective":["vertical":31]]]))
        let before=AgentDocument(target)
        let after=try before.merged(with:["decode":["perspective":["vertical":10]]])
        XCTAssertEqual(after.decode.perspective.vertical,10);XCTAssertEqual(after.geometry,before.geometry)
        let session=Session()
        XCTAssertThrowsError(try session.applyAgentEdit(["adjustments":["exposure":1],"decode":["perspective":["vertical":5]]]))
        XCTAssertEqual(session.adjustments.exposure,0)
        let name = "perspective-defaults-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cleanSession = Session(clipboardDefaults: defaults)
        XCTAssertFalse(cleanSession.clipboardGroups.contains(.perspective))
    }
    func testPairIgnoresPerspectiveWithoutErasingTheSingleFrameSetting() {
        var hole=HalfFramePair.Hole(url:URL(fileURLWithPath:"/tmp/source.ARW"))
        hole.decode.perspective=RawPerspective(vertical:15,horizontal:-10)
        XCTAssertTrue(PairComposer.decodeSettings(for:hole).perspective.isNeutral)
        XCTAssertEqual(hole.decode.perspective.vertical,15)
        let before=PairComposer.renderKey(hole,size:CGSize(width:6000,height:4000),hole:CGSize(width:1800,height:2400),aspect:0.75)
        hole.decode.perspective=RawPerspective()
        XCTAssertEqual(before,PairComposer.renderKey(hole,size:CGSize(width:6000,height:4000),hole:CGSize(width:1800,height:2400),aspect:0.75))
    }

    private struct LegacyDecode: Encodable {
        var whiteBalance = DecodeSettings.WhiteBalance.asShot
        var temperature: Double = 5500
        var tint: Double = 0
        var lensCorrection = false
    }

    func testNeutralPerspectiveKeepsTheHistoricalDisplayAndPrintKeys() {
        let url=URL(fileURLWithPath:"/tmp/legacy-neutral.ARW"),settings=DecodeSettings()
        let legacy=LegacyDecode()
        let display=Session.displayCacheKey(url:url,settings:settings,previewLongEdge:2560,engineVersion:"test")
        XCTAssertEqual(display.configuration,CacheKey.encodedConfiguration(legacy))
        var effective=legacy;effective.temperature=0;effective.tint=0
        for tier in [CacheTier.live,.full] {
            let print=Session.printCacheKey(url:url,params:.default,settings:settings,tier:tier,previewLongEdge:2560,engineVersion:"test")
            XCTAssertEqual(print.configuration,"single-print-3;rgba16Unorm;"+CacheKey.encodedConfiguration(effective)+";"+Session.printStamp(.default))
        }
        var corrected=settings;corrected.perspective.vertical=10
        let key=Session.displayCacheKey(url:url,settings:corrected,previewLongEdge:2560,engineVersion:"test")
        XCTAssertTrue(key.configuration.contains("\"horizontal\":0"));XCTAssertTrue(key.configuration.contains("\"vertical\":10"))
    }

    func testNeutralPerspectiveReadsHistoricalDisplayAndOrdinaryPrintCacheValues() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"legacy-perspective-cache-\(UUID())")
        defer {try? FileManager.default.removeItem(at:root)}
        let store=try DiskCacheStore(root:root),url=root.appending(path:"source.ARW")
        let source=CacheKey.sourceIdentity(for:url),legacy=LegacyDecode(),data=Data(repeating:123,count:8)
        var normalized=legacy;normalized.temperature=0;normalized.tint=0
        let oldDisplay=CacheKey(kind:.decode,sourceIdentity:source,configuration:CacheKey.encodedConfiguration(legacy),previewLongEdge:2560,engineVersion:"test")
        let oldPrint=CacheKey(kind:.printLive,sourceIdentity:source,configuration:"single-print-3;rgba16Unorm;"+CacheKey.encodedConfiguration(normalized)+";"+Session.printStamp(.default),tier:.live,previewLongEdge:2560,engineVersion:"test")
        let newDisplay=Session.displayCacheKey(url:url,settings:DecodeSettings(),previewLongEdge:2560,engineVersion:"test")
        let newPrint=Session.printCacheKey(url:url,params:.default,tier:.live,previewLongEdge:2560,engineVersion:"test")
        for (old,new) in [(oldDisplay,newDisplay),(oldPrint,newPrint)] {
            try await store.store(key:old,data:data,width:1,height:1,format:"rgba16Unorm",costMs:1)
            let restored=try await store.load(new)
            XCTAssertEqual(restored?.data,data)
        }
    }

}
