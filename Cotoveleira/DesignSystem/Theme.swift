import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Sistema", light = "Claro", dark = "Escuro"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum Palette {
    static func background(_ dark: Bool) -> Color { Color(hex: dark ? 0x0B0D10 : 0xF5F5F7) }
    static func surface(_ dark: Bool) -> Color { Color(hex: dark ? 0x1C1D21 : 0xFFFFFF) }
    static func primary(_ dark: Bool) -> Color { Color(hex: dark ? 0xF5F5F7 : 0x1D1D1F) }
    static func secondary(_ dark: Bool) -> Color { Color(hex: dark ? 0xA1A1AA : 0x6E6E73) }
    static func blue(_ dark: Bool) -> Color { Color(hex: dark ? 0x0A84FF : 0x007AFF) }
    static func orange(_ dark: Bool) -> Color { Color(hex: dark ? 0xFF9F0A : 0xFF9500) }
    static func green(_ dark: Bool) -> Color { Color(hex: dark ? 0x30D158 : 0x34C759) }
    static let red = Color.red
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface(scheme == .dark), in: RoundedRectangle(cornerRadius: 24))
    }
}
