import DaubCore
import XCTest

final class ToolSettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "daub.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNothingSavedLoadsNothing() {
        XCTAssertNil(ToolSettingsStore(defaults: defaults).load())
    }

    func testEverySettingRoundTrips() {
        var s = ToolSettings()
        s.tool = "brush"
        s.primary = [0.2, 0.4, 0.6, 1]
        s.secondary = [0.9, 0.8, 0.7, 1]
        s.strokeWidth = 17
        s.pencilSize = 5
        s.eraserSize = 40
        s.sprayRadius = 33
        s.sprayDensity = 61
        s.tolerance = 30
        s.brushOpacity = 0.4
        s.shapeStyle = ShapeFill.filledOutline.rawValue
        s.antialias = false
        s.fontSize = 72
        s.fontName = "Menlo"
        s.showGrid = false
        ToolSettingsStore(defaults: defaults).save(s)

        // A second store on the same domain stands in for the next launch.
        XCTAssertEqual(ToolSettingsStore(defaults: UserDefaults(suiteName: suite)!).load(), s)
    }

    func testMissingKeysKeepTheirDefaultsAndTheRestSurvive() {
        defaults.set(Data(#"{"tool":"eraser","eraserSize":50}"#.utf8), forKey: ToolSettingsStore.key)
        let s = ToolSettingsStore(defaults: defaults).load()
        XCTAssertEqual(s?.tool, "eraser")
        XCTAssertEqual(s?.eraserSize, 50)
        XCTAssertEqual(s?.brushOpacity, ToolSettings().brushOpacity)
    }

    func testOutOfRangeAndDamagedValuesAreRepaired() {
        let json = #"""
        {"strokeWidth":900,"brushOpacity":0,"tolerance":-4,"primary":[2,0.5],
         "secondary":[0.5,-1,0.5,1],"shapeStyle":"zigzag","fontName":"","fontSize":"big"}
        """#
        defaults.set(Data(json.utf8), forKey: ToolSettingsStore.key)
        let s = ToolSettingsStore(defaults: defaults).load()!
        XCTAssertEqual(s.strokeWidth, ToolSettings.strokeRange.upperBound)
        XCTAssertEqual(s.brushOpacity, ToolSettings.opacityRange.lowerBound)
        XCTAssertEqual(s.tolerance, 0)
        XCTAssertEqual(s.primary, ToolSettings().primary)
        XCTAssertEqual(s.secondary, [0.5, 0, 0.5, 1])
        XCTAssertEqual(s.shapeStyle, ToolSettings().shapeStyle)
        XCTAssertEqual(s.fontName, ToolSettings().fontName)
        XCTAssertEqual(s.fontSize, ToolSettings().fontSize)
    }

    func testGarbageLoadsNothingRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: ToolSettingsStore.key)
        XCTAssertNil(ToolSettingsStore(defaults: defaults).load())
    }
}
