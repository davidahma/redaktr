import AppKit
import SwiftUI

struct RedaktrHeaderMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}

enum RedaktrUI {
    static let cornerRadius: CGFloat = 8
    static let controlHeight: CGFloat = 36
    static let compactControlWidth: CGFloat = 46
    static let splitControlWidth: CGFloat = 68
    static let controlSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 8
    static let cardSpacing: CGFloat = 12
    static let panelPadding: CGFloat = 28

    static let primaryBlue = Color.accentColor
    static let safeGreen = Color.green
    static let reviewOrange = Color.orange
    static let destructiveRed = Color.red
    static let neutralBorder = Color.secondary.opacity(0.16)

    static var controlSurface: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var cardSurface: Color {
        Color(nsColor: .textBackgroundColor)
    }
}

enum RedaktrControlTone {
    case primary
    case secondary
    case quiet
    case destructive
}

struct RedaktrButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tone: RedaktrControlTone
    let minWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth, minHeight: RedaktrUI.controlHeight)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(configuration), in: RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
            .opacity(isEnabled ? 1 : 0.48)
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary:
            .white
        case .destructive:
            isEnabled ? RedaktrUI.destructiveRed : .secondary
        case .secondary, .quiet:
            .primary
        }
    }

    private func backgroundColor(_ configuration: Configuration) -> Color {
        let pressedOpacity = configuration.isPressed ? 0.72 : 1
        switch tone {
        case .primary:
            return RedaktrUI.primaryBlue.opacity(isEnabled ? pressedOpacity : 0.24)
        case .destructive:
            return RedaktrUI.destructiveRed.opacity(isEnabled ? (configuration.isPressed ? 0.16 : 0.09) : 0.04)
        case .secondary:
            return RedaktrUI.controlSurface.opacity(configuration.isPressed ? 0.72 : 1)
        case .quiet:
            return RedaktrUI.controlSurface.opacity(configuration.isPressed ? 0.55 : 0.62)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            Color.clear
        case .destructive:
            RedaktrUI.destructiveRed.opacity(isEnabled ? 0.22 : 0.08)
        case .secondary, .quiet:
            RedaktrUI.neutralBorder
        }
    }
}

extension ButtonStyle where Self == RedaktrButtonStyle {
    static func redaktr(_ tone: RedaktrControlTone = .secondary, minWidth: CGFloat? = nil) -> RedaktrButtonStyle {
        RedaktrButtonStyle(tone: tone, minWidth: minWidth)
    }
}
