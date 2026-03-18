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
