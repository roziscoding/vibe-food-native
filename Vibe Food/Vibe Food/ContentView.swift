//
//  ContentView.swift
//  Vibe Food
//
//  Created by Rogério Munhoz on 01/03/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dayStore = appContainer.daySelectionStore
        TabView(
            selection: Binding(
                get: { appContainer.selectedTab },
                set: { appContainer.selectedTab = $0 }
            )
        ) {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "house") }
                .tag(AppTab.dashboard)

            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife.circle") }
                .tag(AppTab.food)

            InputView()
                .tabItem {
                    Label {
                        Text("Input")
                    } icon: {
#if canImport(UIKit)
                        Image(uiImage: inputTabIconImage())
#else
                        Image(systemName: "plus.circle.fill")
#endif
                    }
                }
                .tag(AppTab.input)

            WaterView()
                .tabItem { Label("Water", systemImage: "drop") }
                .tag(AppTab.water)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(AppGlass.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .environment(dayStore)
        .onAppear {
            configureTabBarAppearance(for: colorScheme)
        }
        .onChange(of: colorScheme) { _, newValue in
            configureTabBarAppearance(for: newValue)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppContainer())
}

#if canImport(UIKit)
private func configureTabBarAppearance(for colorScheme: ColorScheme) {
    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundEffect = UIBlurEffect(
        style: colorScheme == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
    )
    appearance.backgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.white.withAlphaComponent(0.72)
    }
    appearance.shadowColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.15)
            : UIColor.black.withAlphaComponent(0.08)
    }
    appearance.selectionIndicatorImage = selectionIndicatorImage(for: colorScheme)

    let selectedColor = UIColor.systemBlue
    let normalColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.62)
            : UIColor.secondaryLabel
    }

    let selected = appearance.stackedLayoutAppearance.selected
    selected.iconColor = selectedColor
    selected.titleTextAttributes = [.foregroundColor: selectedColor]

    let normal = appearance.stackedLayoutAppearance.normal
    normal.iconColor = normalColor
    normal.titleTextAttributes = [.foregroundColor: normalColor]

    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
    UITabBar.appearance().isTranslucent = true
}

private func selectionIndicatorImage(for colorScheme: ColorScheme) -> UIImage? {
    let size = CGSize(width: 86, height: 50)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        let rect = CGRect(x: 7, y: 5, width: size.width - 14, height: size.height - 10)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 24)

        context.cgContext.setShadow(
            offset: .zero,
            blur: 2,
            color: UIColor.systemBlue.withAlphaComponent(0.15).cgColor
        )
        (
            colorScheme == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.52)
        ).setFill()
        path.fill()

        context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        let border = path.cgPath
        context.cgContext.addPath(border)
        context.cgContext.replacePathWithStrokedPath()
        context.cgContext.clip()
        let colors = [
            UIColor(red: 0.78, green: 0.96, blue: 1.0, alpha: 0.55).cgColor,
            UIColor(red: 0.80, green: 0.71, blue: 1.0, alpha: 0.38).cgColor
        ] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }

    return image.resizableImage(
        withCapInsets: UIEdgeInsets(top: 24, left: 32, bottom: 24, right: 32),
        resizingMode: .stretch
    )
}

private func inputTabIconImage() -> UIImage {
    let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    let base = UIImage(systemName: "plus.circle.fill", withConfiguration: configuration)
        ?? UIImage(systemName: "plus.circle.fill")
        ?? UIImage()
    return base.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
}
#endif
