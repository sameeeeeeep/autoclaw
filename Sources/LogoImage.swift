import SwiftUI

/// Loads the Autoclaw logo from the app bundle at the requested size.
struct LogoImage: View {
    var size: CGFloat = 24

    var body: some View {
        if let path = Bundle.main.path(forResource: "autoclaw_logo", ofType: "png"),
           let nsImg = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImg)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

/// Menubar icon from the app bundle, tinted with a color overlay.
/// Uses the menubar_icon.png as a template and applies color.
struct MenuBarIconView: View {
    var color: Color = .green
    var size: CGFloat = 14

    var body: some View {
        if let path = Bundle.main.path(forResource: "menubar_icon", ofType: "png"),
           let nsImg = NSImage(contentsOfFile: path) {
            let _ = { nsImg.isTemplate = true }()
            Image(nsImage: nsImg)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(color)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(color)
        }
    }
}
