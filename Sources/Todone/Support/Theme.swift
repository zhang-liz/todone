import SwiftUI
import TodoneKit

/// A named accent theme, Todoist-style.
struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let accentHex: String

    var accent: Color { Color(hex: accentHex) }

    static let all: [AppTheme] = [
        AppTheme(id: "todoneRed", name: "Todone Red", accentHex: "#DC4C3E"),
        AppTheme(id: "sunflower", name: "Sunflower", accentHex: "#EBA950"),
        AppTheme(id: "clover", name: "Clover", accentHex: "#3F9C71"),
        AppTheme(id: "sky", name: "Sky", accentHex: "#2E86C1"),
        AppTheme(id: "blueberry", name: "Blueberry", accentHex: "#3D5AFE"),
        AppTheme(id: "lavender", name: "Lavender", accentHex: "#8E7CC3"),
        AppTheme(id: "raspberry", name: "Raspberry", accentHex: "#D64570"),
        AppTheme(id: "sable", name: "Sable", accentHex: "#546E7A"),
        AppTheme(id: "tangerine", name: "Tangerine", accentHex: "#E8654A"),
        AppTheme(id: "moss", name: "Moss", accentHex: "#7C8B45"),
    ]

    static func theme(id: String) -> AppTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    init(_ itemColor: ItemColor) {
        self.init(hex: itemColor.hex)
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .p1: return Color(hex: "#D1453B")
        case .p2: return Color(hex: "#EB8909")
        case .p3: return Color(hex: "#246FE0")
        case .p4: return Color.secondary
        }
    }

    var flagName: String {
        self == .p4 ? "flag" : "flag.fill"
    }
}
