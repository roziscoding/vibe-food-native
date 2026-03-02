import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppGlass {
    static let accent = Color(uiColor: .systemBlue)
    static let accentSecondary = Color(uiColor: .systemIndigo)
    static let backgroundBase = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.97, blue: 0.995, alpha: 1),
        dark: UIColor(red: 0.0157, green: 0.0235, blue: 0.0392, alpha: 1)
    )
    static let backgroundTop = adaptiveColor(
        light: UIColor(red: 0.83, green: 0.89, blue: 0.98, alpha: 0.45),
        dark: UIColor(red: 0.06, green: 0.09, blue: 0.15, alpha: 0.33)
    )
    static let backgroundMiddle = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.97, blue: 0.995, alpha: 1),
        dark: UIColor(red: 0.0157, green: 0.0235, blue: 0.0392, alpha: 1)
    )
    static let backgroundBottom = adaptiveColor(
        light: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.0157, green: 0.0235, blue: 0.0392, alpha: 1)
    )
    static let metallicShine = adaptiveColor(
        light: UIColor.clear,
        dark: UIColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 0.075)
    )
    static let metallicGlow = adaptiveColor(
        light: UIColor.clear,
        dark: UIColor(red: 0.33, green: 0.55, blue: 0.78, alpha: 0.0675)
    )
    static let primaryFill = adaptiveColor(
        light: UIColor.white.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let secondaryFill = adaptiveColor(
        light: UIColor.white.withAlphaComponent(0.10),
        dark: UIColor.white.withAlphaComponent(0.04)
    )
    static let primaryBorderStart = adaptiveColor(
        light: UIColor(red: 0.71, green: 0.87, blue: 0.99, alpha: 0.36),
        dark: UIColor(red: 0.78, green: 0.96, blue: 1.0, alpha: 0.18)
    )
    static let primaryBorderEnd = adaptiveColor(
        light: UIColor(red: 0.79, green: 0.73, blue: 0.98, alpha: 0.28),
        dark: UIColor(red: 0.80, green: 0.71, blue: 1.0, alpha: 0.12)
    )
    static let secondaryBorder = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let panelHighlight = adaptiveColor(
        light: UIColor.white.withAlphaComponent(0.05),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let shadowColor = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.black.withAlphaComponent(0.13)
    )
    static let primaryUnderlay = adaptiveColor(
        light: UIColor.white.withAlphaComponent(0.04),
        dark: UIColor.black.withAlphaComponent(0.18)
    )
    static let secondaryUnderlay = adaptiveColor(
        light: UIColor.white.withAlphaComponent(0.08),
        dark: UIColor.black.withAlphaComponent(0.10)
    )
    static let controlFill = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.045),
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let noiseColor = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.016),
        dark: UIColor.white.withAlphaComponent(0.015)
    )
    static let textPrimary = Color(uiColor: .label).opacity(0.96)
    static let textSecondary = Color(uiColor: .label).opacity(0.86)
    static let textMuted = Color(uiColor: .secondaryLabel).opacity(0.95)
    static let textSubtle = Color(uiColor: .tertiaryLabel).opacity(0.96)
    static let textFaint = Color(uiColor: .quaternaryLabel).opacity(0.98)

    static let sectionSpacing: CGFloat = 12
    static let cardSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 24
    static let pillCornerRadius: CGFloat = 26
    static let heroPadding: CGFloat = 24
    static let bodyFontSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 4
    static let sectionTracking: CGFloat = 0.24

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum AppGlassWeight {
    case primary
    case secondary
}

struct AppGlassBackground: View {
    var body: some View {
        ZStack {
            AppGlass.backgroundBase
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AppGlass.backgroundTop,
                    AppGlass.backgroundMiddle,
                    AppGlass.backgroundBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .clear,
                    AppGlass.metallicShine,
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .clear,
                    AppGlass.metallicGlow,
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blur(radius: 40)
            .ignoresSafeArea()

            Circle()
                .fill(AppGlass.accent.opacity(0.035))
                .frame(width: 260, height: 260)
                .blur(radius: 140)
                .offset(x: -120, y: -280)

            Circle()
                .fill(AppGlass.accentSecondary.opacity(0.03))
                .frame(width: 250, height: 250)
                .blur(radius: 150)
                .offset(x: 130, y: -170)

            AppGlassNoise()
                .ignoresSafeArea()
        }
    }
}

struct AppGlassNoise: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for index in 0..<180 {
                    let x = pseudoRandom(index * 17 + 11) * size.width
                    let y = pseudoRandom(index * 29 + 7) * size.height
                    let radius = 0.6 + pseudoRandom(index * 13 + 5) * 1.8
                    let opacity = 0.01 + pseudoRandom(index * 19 + 3) * 0.015
                    let rect = CGRect(x: x, y: y, width: radius, height: radius)
                    context.fill(Path(ellipseIn: rect), with: .color(AppGlass.noiseColor.opacity(opacity)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .blendMode(.softLight)
            .opacity(0.32)
        }
    }

    private func pseudoRandom(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let weight: AppGlassWeight

    func body(content: Content) -> some View {
        content
            .background {
                panelBackground
            }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(iOS 26.0, *) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(weight == .primary ? AppGlass.primaryUnderlay : AppGlass.secondaryUnderlay)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(glassStyle, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        weight == .primary
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppGlass.primaryBorderStart,
                                        AppGlass.primaryBorderEnd
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppGlass.secondaryBorder),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowYOffset
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(weight == .primary ? .regularMaterial : .ultraThinMaterial)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(weight == .primary ? AppGlass.primaryFill : AppGlass.secondaryFill)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                                colors: [
                                AppGlass.panelHighlight.opacity(weight == .primary ? 1 : 0.55),
                                .clear,
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        weight == .primary
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppGlass.primaryBorderStart,
                                        AppGlass.primaryBorderEnd
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppGlass.secondaryBorder),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowYOffset
            )
        }
    }

    private var shadowColor: Color {
        let baseOpacity: Double
        if colorScheme == .light {
            baseOpacity = 0
        } else {
            baseOpacity = weight == .primary ? 1.0 : 0.72
        }
        return AppGlass.shadowColor.opacity(baseOpacity)
    }

    private var shadowRadius: CGFloat {
        if colorScheme == .light {
            return 0
        }
        return weight == .primary ? 18 : 16
    }

    private var shadowYOffset: CGFloat {
        if colorScheme == .light {
            return 0
        }
        return weight == .primary ? 6 : 4
    }

    @available(iOS 26.0, *)
    private var glassStyle: Glass {
        .regular
    }
}

struct AppScreenHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                if let trailing {
                    trailing
                }
            }
        }
    }
}

struct AppSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .textCase(.uppercase)
            .tracking(AppGlass.sectionTracking)
            .foregroundStyle(AppGlass.textSubtle)
    }
}

struct AppBodyText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: AppGlass.bodyFontSize, weight: .medium, design: .rounded))
            .lineSpacing(AppGlass.bodyLineSpacing)
    }
}

struct AppHeroCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppGlass.heroPadding)
            .background {
                ZStack {
                    Circle()
                        .fill(AppGlass.accent.opacity(0.05))
                        .frame(width: 220, height: 220)
                        .blur(radius: 96)
                        .offset(x: -90, y: -10)

                    Circle()
                        .fill(AppGlass.accentSecondary.opacity(0.04))
                        .frame(width: 220, height: 220)
                        .blur(radius: 104)
                        .offset(x: 120, y: 0)

                    RoundedRectangle(cornerRadius: AppGlass.cardCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppGlass.shadowColor.opacity(0.18),
                                    .clear,
                                    AppGlass.shadowColor.opacity(0.14)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: AppGlass.cardCornerRadius, style: .continuous))
            }
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }
}

struct AppIconGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: active ? AppGlass.accent.opacity(0.15) : .clear,
                radius: active ? 2 : 0,
                y: 0
            )
            .foregroundStyle(active ? AppGlass.textPrimary : AppGlass.textMuted)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 24, weight: AppGlassWeight = .secondary) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, weight: weight))
    }

    func appBodyText() -> some View {
        modifier(AppBodyText())
    }

    func appHeroCard() -> some View {
        modifier(AppHeroCard())
    }

    func appIconGlow(active: Bool) -> some View {
        modifier(AppIconGlow(active: active))
    }
}
