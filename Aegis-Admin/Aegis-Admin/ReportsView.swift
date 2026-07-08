import SwiftUI

struct ReportsView: View {
    @ObservedObject var viewModel: ReportsViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Reports")
                    .screenTitle()

                WhitePanel {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Generate Attendance Rollup", systemImage: "doc.text.fill")
                            .font(.system(size: 16, weight: .bold))

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 28) {
                                reportFields
                                reportResult
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 18) {
                                reportFields
                                reportResult
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                Task { await viewModel.runRollup(sessionStore: sessionStore) }
                            } label: {
                                Label(viewModel.isRunning ? "Running..." : "Run Rollup", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 34)
                                    .background(AegisColors.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isRunning)
                        }

                        if case let .failed(message) = viewModel.state {
                            ErrorBanner(message: message)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)

                Spacer(minLength: 0)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reportFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormTextField(title: "Date", text: $viewModel.dateText)
                .frame(width: 190)
            FormTextField(title: "User ID", text: $viewModel.userIDText)
                .frame(width: 190)
        }
    }

    private var reportResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    RollupMetric(title: "Processed", value: "\(viewModel.result?.processed ?? 0)")
                    RollupMetric(title: "Leave Skipped", value: "\(viewModel.result?.skippedLeave ?? 0)")
                }

                VStack(alignment: .leading, spacing: 12) {
                    RollupMetric(title: "Processed", value: "\(viewModel.result?.processed ?? 0)")
                    RollupMetric(title: "Leave Skipped", value: "\(viewModel.result?.skippedLeave ?? 0)")
                }
            }

            if let message = viewModel.message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(message == "Rollup completed" ? AegisColors.activeGreen : Color.red)
            }
        }
    }
}

private struct RollupMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
        }
        .padding(16)
        .frame(width: 150, alignment: .leading)
        .background(AegisColors.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}
