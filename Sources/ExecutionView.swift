import SwiftUI

struct ExecutionView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if appState.isExecuting {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Executing...")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Complete")
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(appState.executionOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("output")
                }
                .onChange(of: appState.executionOutput) { _ in
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
            .frame(maxHeight: 300)
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)
        }
        .padding(16)
    }
}
