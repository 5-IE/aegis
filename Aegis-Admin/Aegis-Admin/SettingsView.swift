import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text("Settings")
                    .screenTitle()

                WhitePanel {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("Attendance Setting", systemImage: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))

                        SettingsSubpanel(title: "Session Thresholds", icon: "clock") {
                            VStack(spacing: 18) {
                                SessionThresholdRow(title: "AM Session", config: $viewModel.sessionConfigs.am)
                                SessionThresholdRow(title: "PM Session", config: $viewModel.sessionConfigs.pm)
                            }
                        }

                        SettingsSubpanel(title: "Late Check-in", icon: "clock.badge.exclamationmark") {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) {
                                    TimeField(text: $viewModel.sessionConfigs.am.lateAfter)
                                    Text("AM tolerance")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AegisColors.mutedText)
                                    TimeField(text: $viewModel.sessionConfigs.pm.lateAfter)
                                    Text("PM tolerance")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AegisColors.mutedText)
                                    Spacer()
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        TimeField(text: $viewModel.sessionConfigs.am.lateAfter)
                                        Text("AM tolerance")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AegisColors.mutedText)
                                    }
                                    HStack(spacing: 12) {
                                        TimeField(text: $viewModel.sessionConfigs.pm.lateAfter)
                                        Text("PM tolerance")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AegisColors.mutedText)
                                    }
                                }
                            }
                            Text("Check-ins after the late threshold are marked late by the backend.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AegisColors.mutedText)
                        }

                        Label("User Presence Update Interval", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.top, 4)

                        SettingsSubpanel(title: "Adjust Interval", icon: "arrow.clockwise") {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    presenceStepper
                                    Spacer()
                                    timezoneField
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    presenceStepper
                                    timezoneField
                                }
                            }
                            Text("Set how long a presence ping stays active before the user is considered stale.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AegisColors.mutedText)
                        }

                        HStack {
                            if let message = viewModel.saveMessage {
                                Text(message)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(message == "Settings saved" ? AegisColors.activeGreen : Color.red)
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.save(sessionStore: sessionStore) }
                            } label: {
                                Text(viewModel.isSaving ? "Saving..." : "Save Settings")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 34)
                                    .background(AegisColors.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isSaving)
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)

                Spacer(minLength: 0)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if viewModel.state == .idle {
                await viewModel.load(sessionStore: sessionStore)
            }
        }
    }

    private var presenceStepper: some View {
        Stepper(value: $viewModel.systemConfig.presenceStalenessMinutes, in: 1...60) {
            Text("\(viewModel.systemConfig.presenceStalenessMinutes) minutes")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 220)
    }

    private var timezoneField: some View {
        TextField("Timezone", text: $viewModel.systemConfig.timezone)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
    }
}

private struct SettingsSubpanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AegisColors.teal)
            content
        }
        .padding(20)
        .background(AegisColors.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
        .shadow(color: AegisColors.cardShadow, radius: 6, x: 0, y: 3)
    }
}

private struct SessionThresholdRow: View {
    let title: String
    @Binding var config: SessionConfig

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                rowTitle
                TimeField(text: $config.startTime)
                SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                Text("to")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)
                TimeField(text: $config.endTime)
                SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                rowTitle
                HStack(spacing: 12) {
                    TimeField(text: $config.startTime)
                    SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                    Text("to")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AegisColors.mutedText)
                    TimeField(text: $config.endTime)
                    SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                }
            }
        }
    }

    private var rowTitle: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 110, alignment: .leading)
    }
}

private struct TimeField: View {
    @Binding var text: String

    var body: some View {
        TextField("00:00:00", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(width: 88, height: 25)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }
}

private struct SessionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AegisColors.teal)
            .frame(width: 49, height: 25)
            .background(Color.black.opacity(0.04))
            .clipShape(Capsule())
    }
}
