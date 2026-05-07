import RecordCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        VStack(spacing: 24) {
            previewPanel
            controlsPanel
            footerPanel
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var previewPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.88))

            if let image = viewModel.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Waiting for camera preview")
                        .foregroundStyle(.white.opacity(0.82))
                }
            }

            VStack {
                HStack {
                    statusBadge
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
        }
        .frame(minHeight: 520)
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
    }

    private var controlsPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            configCard(title: "Input Devices") {
                VStack(spacing: 14) {
                    labeledPicker(
                        title: "Camera",
                        selection: $viewModel.selectedVideoDeviceID,
                        items: viewModel.videoDevices
                    ) { deviceID in
                        Task { await viewModel.selectVideoDevice(deviceID) }
                    }
                    labeledPicker(
                        title: "Microphone",
                        selection: $viewModel.selectedAudioDeviceID,
                        items: viewModel.audioDevices
                    ) { deviceID in
                        Task { await viewModel.selectAudioDevice(deviceID) }
                    }
                }
            }

            configCard(title: "Resolution") {
                HStack(spacing: 12) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        Button {
                            viewModel.selectResolution(preset)
                        } label: {
                            VStack(spacing: 6) {
                                Text(preset.title)
                                    .font(.headline)
                                Text(viewModel.availability(for: preset) == .available ? "Ready" : "Unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.selectedResolution == preset ? .red : .gray.opacity(0.65))
                        .disabled(viewModel.availability(for: preset) == .unavailable)
                    }
                }
            }

            configCard(title: "Effects & Export") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $viewModel.virtualBackgroundEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("White virtual background")
                            Text("Applies person segmentation and keeps the effect in the exported mp4.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Button {
                        Task { await viewModel.toggleRecording() }
                    } label: {
                        Text(viewModel.primaryButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(viewModel.isRecording ? .orange : .red)

                    if viewModel.needsExportPath {
                        Button("Choose Save Location") {
                            Task { await viewModel.chooseSaveLocation() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var footerPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text("Recording mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Camera only")
                    .font(.headline)
                Text("Screen capture is reserved for a later iteration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.22))
            )
            .foregroundStyle(statusColor)
    }

    private var statusTitle: String {
        switch viewModel.phase {
        case .booting:
            return "Booting"
        case .previewReady:
            return "Preview Ready"
        case .recording:
            return "Recording"
        case .awaitingExportPath:
            return "Awaiting Export Path"
        case .exporting:
            return "Exporting"
        case .exportComplete:
            return "Export Complete"
        case .error:
            return "Attention"
        }
    }

    private var statusColor: Color {
        switch viewModel.phase {
        case .booting:
            return .yellow
        case .previewReady:
            return .mint
        case .recording:
            return .red
        case .awaitingExportPath:
            return .orange
        case .exporting:
            return .blue
        case .exportComplete:
            return .green
        case .error:
            return .orange
        }
    }

    private func configCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func labeledPicker(
        title: String,
        selection: Binding<String>,
        items: [DeviceDescriptor],
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Picker(title, selection: selection) {
                ForEach(items) { item in
                    Text(item.name).tag(item.id)
                }
            }
            .labelsHidden()
            .disabled(!viewModel.canConfigureDevices)
            .onChange(of: selection.wrappedValue) { _, newValue in
                onChange(newValue)
            }
        }
    }
}
