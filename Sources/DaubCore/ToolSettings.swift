import Foundation

/// The toolbox as the user last left it, kept across launches. Colours are sRGB
/// components; the tool and shape style are raw values so the app's enums stay in the app.
public struct ToolSettings: Codable, Equatable, Sendable {
    public var tool = "pencil"
    public var primary: [Double] = [0, 0, 0, 1]
    public var secondary: [Double] = [1, 1, 1, 1]
    public var strokeWidth: Double = 3
    public var pencilSize: Double = 1
    public var eraserSize: Double = 12
    public var sprayRadius: Double = 14
    public var sprayDensity: Double = 20
    public var tolerance: Double = 0
    public var brushOpacity: Double = 1
    public var shapeStyle = ShapeFill.outline.rawValue
    public var antialias = true
    public var fontSize: Double = 28
    public var fontName = "Helvetica Neue"
    public var showGrid = true

    public init() {}

    public static let pencilRange: ClosedRange<Double> = 1...16
    public static let strokeRange: ClosedRange<Double> = 1...48
    public static let eraserRange: ClosedRange<Double> = 1...96
    public static let sprayRadiusRange: ClosedRange<Double> = 2...80
    public static let sprayDensityRange: ClosedRange<Double> = 1...80
    public static let toleranceRange: ClosedRange<Double> = 0...128
    public static let opacityRange: ClosedRange<Double> = 0.05...1
    public static let fontSizeRange: ClosedRange<Double> = 8...144

    /// Every key is optional so that a file written by an older or newer build loses only
    /// the settings it does not share, not all of them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ToolSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        tool = v(.tool, d.tool)
        primary = v(.primary, d.primary)
        secondary = v(.secondary, d.secondary)
        strokeWidth = v(.strokeWidth, d.strokeWidth)
        pencilSize = v(.pencilSize, d.pencilSize)
        eraserSize = v(.eraserSize, d.eraserSize)
        sprayRadius = v(.sprayRadius, d.sprayRadius)
        sprayDensity = v(.sprayDensity, d.sprayDensity)
        tolerance = v(.tolerance, d.tolerance)
        brushOpacity = v(.brushOpacity, d.brushOpacity)
        shapeStyle = v(.shapeStyle, d.shapeStyle)
        antialias = v(.antialias, d.antialias)
        fontSize = v(.fontSize, d.fontSize)
        fontName = v(.fontName, d.fontName)
        showGrid = v(.showGrid, d.showGrid)
        self = sanitized()
    }

    /// Values the sliders could never have produced (a hand-edited or damaged file) are
    /// pulled back into range rather than handed to the painting code.
    public func sanitized() -> ToolSettings {
        let d = ToolSettings()
        var s = self
        func fit(_ x: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double {
            x.isFinite ? min(max(x, r.lowerBound), r.upperBound) : fallback
        }
        func colour(_ c: [Double], _ fallback: [Double]) -> [Double] {
            guard c.count == 4, c.allSatisfy(\.isFinite) else { return fallback }
            return c.map { min(max($0, 0), 1) }
        }
        s.primary = colour(primary, d.primary)
        s.secondary = colour(secondary, d.secondary)
        s.strokeWidth = fit(strokeWidth, Self.strokeRange, d.strokeWidth)
        s.pencilSize = fit(pencilSize, Self.pencilRange, d.pencilSize)
        s.eraserSize = fit(eraserSize, Self.eraserRange, d.eraserSize)
        s.sprayRadius = fit(sprayRadius, Self.sprayRadiusRange, d.sprayRadius)
        s.sprayDensity = fit(sprayDensity, Self.sprayDensityRange, d.sprayDensity)
        s.tolerance = fit(tolerance, Self.toleranceRange, d.tolerance)
        s.brushOpacity = fit(brushOpacity, Self.opacityRange, d.brushOpacity)
        s.fontSize = fit(fontSize, Self.fontSizeRange, d.fontSize)
        if ShapeFill(rawValue: shapeStyle) == nil { s.shapeStyle = d.shapeStyle }
        if fontName.isEmpty { s.fontName = d.fontName }
        return s
    }
}

/// Writes on every change rather than on quit, so a crash or a force-quit keeps the
/// settings: `UserDefaults` hands each write to the preferences daemon, which outlives us.
public struct ToolSettingsStore {
    public static let key = "toolSettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> ToolSettings? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(ToolSettings.self, from: data)
    }

    public func save(_ settings: ToolSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
