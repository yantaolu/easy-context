import SwiftUI
import EasyContextCore

/// 紧凑的版本/手动检查入口；不自行联网，也不持有业务 SettingsStore。
struct UpdateSettingsView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "v\(controller.productVersion)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(fullVersionText)
            Button {
                controller.checkManually()
            } label: {
                Group {
                    if controller.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(controller.isChecking)
            .help("Check for Updates")
            .accessibilityLabel(Text("Check for Updates"))
        }
        .alert(item: $controller.presentedAlert, content: updateAlert)
        .onDisappear { controller.cancelPresentation() }
    }

    private var fullVersionText: String {
        String(format: String(localized: "Version %@ (%@)"),
               controller.productVersion, controller.buildNumber)
    }

    private func updateAlert(_ state: UpdateController.UpdateAlert) -> Alert {
        switch state {
        case .available(let release):
            return Alert(
                title: Text("Update Available"),
                message: Text(String(format: String(localized: "Version %@ is available."),
                                     release.version.description)),
                primaryButton: .default(Text("Download on GitHub")) {
                    controller.openRelease(release)
                },
                secondaryButton: .cancel(Text("Cancel")))
        case .upToDate:
            return Alert(
                title: Text("You're up to date."),
                message: Text(String(format: String(localized: "Easy Context v%@ (%@) is the latest version."),
                                     controller.productVersion, controller.buildNumber)),
                dismissButton: .default(Text("OK")))
        case .failed(let failure):
            return Alert(
                title: Text("Couldn't check for updates."),
                message: failureMessage(failure).map { Text(verbatim: $0) },
                dismissButton: .default(Text("OK")))
        }
    }

    private func failureMessage(_ failure: UpdateCheckFailure) -> String? {
        switch failure {
        case .timedOut:
            return String(localized: "The update check timed out.")
        case .rateLimited:
            return String(localized: "GitHub is temporarily limiting update checks. Try again later.")
        case .network:
            return String(localized: "Please check your internet connection and try again.")
        default:
            return nil
        }
    }
}
