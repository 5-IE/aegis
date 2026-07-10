import AppKit
import SwiftUI

struct ReportsView: View {
    @ObservedObject var viewModel: ReportsViewModel
    @ObservedObject var sessionStore: SessionStore

    @State private var scope: ReportScope = .allLearners
    @State private var period: ReportPeriod = .dateRange
    @State private var fromMonth = Calendar.current.date(
        from: DateComponents(year: 2026, month: 5, day: 1)
    ) ?? Date()
    @State private var toMonth = Calendar.current.date(
        from: DateComponents(year: 2026, month: 6, day: 1)
    ) ?? Date()
    @State private var attendanceStatus = "All Status"
    @State private var exportFormat = "Export as PDF"
    @State private var learnerSearch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Reports")
                    .aegisH1()

                reportPanel
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reportPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Generate Attendance Report", systemImage: "clipboard")
                .aegisH2()
                .padding(.horizontal, 38)
                .frame(height: 76)

            Divider()

            scopeSection
                .padding(.horizontal, 38)
                .frame(height: scope == .individual ? 150 : 112)

            Divider()

            periodSection
                .padding(.horizontal, 38)
                .frame(minHeight: 184)

            Divider()

            exportSection
                .padding(38)
        }
        .background(AegisColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var scopeSection: some View {
        HStack(alignment: .center) {
            sectionDescription(
                title: "Report Scope",
                subtitle: "Choose whose attendance data you want to include"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 54) {
                    radioOption("All learners", value: ReportScope.allLearners, selection: $scope)
                    radioOption("Individual", value: ReportScope.individual, selection: $scope)
                }

                if scope == .individual {
                    SearchField(text: $learnerSearch, placeholder: "Search learner...")
                        .frame(height: 34)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var periodSection: some View {
        HStack(alignment: .top) {
            sectionDescription(
                title: "Period",
                subtitle: "Choose the time period for your report"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 30)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 54) {
                    radioOption("Single Month", value: ReportPeriod.singleMonth, selection: $period)
                    radioOption("Date Range", value: ReportPeriod.dateRange, selection: $period)
                }

                Text(period == .dateRange ? "Select a start and end month" : "Select a month")
                    .font(AegisTypography.caption)
                    .foregroundStyle(AegisColors.mutedText)
                    .padding(.leading, period == .dateRange ? 250 : 0)

                if period == .singleMonth {
                    monthSelector(title: "Month", date: $fromMonth)
                        .frame(width: 230)
                } else {
                    HStack(alignment: .top, spacing: 50) {
                        monthSelector(title: "From", date: $fromMonth)
                            .frame(width: 224)
                        monthSelector(title: "To", date: $toMonth)
                            .frame(width: 224)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 28)
        }
        .onChange(of: fromMonth) { _, newFromMonth in
            if toMonth < newFromMonth {
                toMonth = Calendar.current.date(
                    byAdding: .month,
                    value: 1,
                    to: newFromMonth
                ) ?? newFromMonth
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 70) {
                reportMenu(title: "Attendance Status", selection: $attendanceStatus, options: [
                    "All Status", "Present", "Leave"
                ])
                reportMenu(title: "Export Format", selection: $exportFormat, options: [
                    "Export as PDF", "Export as Excel File"
                ])
            }

            HStack {
                if let outcome = viewModel.reportOutcome {
                    Text(outcome.text)
                        .font(AegisTypography.caption)
                        .foregroundStyle(outcome.isSuccess ? AegisColors.activeGreen : .red)
                }

                Spacer()

                Button {
                    prepareRequest()
                    Task { await downloadReport() }
                } label: {
                    Label(
                        isExporting ? "Downloading..." : "Download Report",
                        systemImage: "square.and.arrow.down"
                    )
                    .font(AegisTypography.b2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background { AegisButtonBackground() }
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }

            if case let .failed(message) = viewModel.reportState {
                ErrorBanner(message: message)
            }
        }
    }

    private func sectionDescription(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .aegisH2()
                .foregroundStyle(AegisColors.teal)
            Text(subtitle)
                .font(AegisTypography.caption)
                .foregroundStyle(AegisColors.mutedText)
        }
    }

    private func radioOption<Value: Hashable>(
        _ title: String,
        value: Value,
        selection: Binding<Value>
    ) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            selection.wrappedValue == value ? AegisColors.teal : Color.gray.opacity(0.65),
                            lineWidth: 2
                        )
                    if selection.wrappedValue == value {
                        Circle()
                            .fill(AegisColors.teal)
                            .padding(5)
                    }
                }
                .frame(width: 20, height: 20)

                Text(title)
                    .font(AegisTypography.b2)
                    .foregroundStyle(.black)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(width: 170, height: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func monthSelector(title: String, date: Binding<Date>) -> some View {
        MonthYearPicker(title: title, date: date)
            .frame(maxWidth: .infinity)
    }

    private func reportMenu(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .aegisH2()
                .foregroundStyle(AegisColors.teal)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(AegisTypography.b2)
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.gray.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var isExporting: Bool {
        viewModel.isGeneratingReport || viewModel.isDownloadingCSV
    }

    private func prepareRequest() {
        let calendar = Calendar.current
        viewModel.reportFromDate = calendar.startOfDay(for: fromMonth)
        viewModel.reportToDate = period == .singleMonth ? endOfMonth(for: fromMonth) : endOfMonth(for: toMonth)
        if scope == .allLearners {
            viewModel.userIDText = ""
        }
    }

    private func downloadReport() async {
        if exportFormat == "Export as PDF" {
            await downloadPDFReport()
        } else {
            await downloadCSVReport()
        }
    }

    private func downloadCSVReport() async {
        guard let data = await viewModel.downloadCSVData(sessionStore: sessionStore) else {
            return
        }
        await saveReport(data, filename: viewModel.suggestedCSVFilename)
    }

    private func downloadPDFReport() async {
        await viewModel.generateReport(sessionStore: sessionStore)
        guard let report = viewModel.report else {
            return
        }
        await saveReport(makeAttendanceReportPDF(report), filename: viewModel.suggestedPDFFilename)
    }

    private func saveReport(_ data: Data, filename: String) async {
        do {
            let downloadsURL = try FileManager.default.url(
                for: .downloadsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = downloadsURL.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)
            viewModel.reportOutcome = .success("Report saved to Downloads")
        } catch {
            viewModel.reportOutcome = .failure("Could not save report: \(error.localizedDescription)")
        }
    }

    private func endOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            return calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: endDate)
    }

    private func makeAttendanceReportPDF(_ report: AttendanceReport) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }

        let left: CGFloat = 54
        let maxY: CGFloat = pageRect.height - 54
        var y: CGFloat = 54
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.black
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]

        func beginPage() {
            context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
            y = 54
        }

        func endPage() {
            context.endPDFPage()
        }

        func ensureSpace(_ height: CGFloat) {
            if y + height > maxY {
                endPage()
                beginPage()
            }
        }

        func draw(_ text: String, attributes: [NSAttributedString.Key: Any] = bodyAttributes, height: CGFloat = 16) {
            ensureSpace(height)
            (text as NSString).draw(
                in: CGRect(x: left, y: y, width: pageRect.width - (left * 2), height: height),
                withAttributes: attributes
            )
            y += height
        }

        beginPage()
        draw("Aegis Attendance Report", attributes: titleAttributes, height: 28)
        draw("\(report.from) to \(report.to)", height: 18)
        y += 10
        draw("Summary", attributes: headingAttributes, height: 20)
        draw("Learners: \(report.summary.learners)")
        draw("Attendance rate: \(formatRatePercent(report.summary.attendanceRate))")
        draw("Total late: \(report.summary.totalLate)")
        draw("Total absent: \(report.summary.totalAbsent)")
        y += 10
        draw("Learners", attributes: headingAttributes, height: 20)
        draw("Name | Session | Present | Late | Absent | Rate", attributes: headingAttributes)
        for learner in report.perLearner {
            draw("\(learner.name) | \(learner.session) | \(learner.present) | \(learner.late) | \(learner.absent) | \(formatRatePercent(learner.attendanceRate))")
        }
        y += 10
        draw("Records", attributes: headingAttributes, height: 20)
        draw("Date | Name | Session | Status | Clock in | Clock out", attributes: headingAttributes)
        for record in report.records {
            draw("\(record.date) | \(record.name) | \(record.session) | \(record.status.titleCasedStatus) | \(formatDateTime(record.clockedInAt)) | \(formatDateTime(record.clockedOutAt))")
        }
        endPage()
        context.closePDF()
        return data as Data
    }
}

private enum ReportScope: Hashable {
    case allLearners
    case individual
}

private enum ReportPeriod: Hashable {
    case singleMonth
    case dateRange
}

private struct MonthYearPicker: View {
    let title: String
    @Binding var date: Date
    @State private var isPresented = false

    private let calendar = Calendar.current
    private let months = Calendar.current.monthSymbols
    private let years = Array(2010...2040)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AegisTypography.caption)

            Button {
                isPresented.toggle()
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(date.formatted(.dateTime.month(.wide).year()))
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(AegisTypography.b2)
                .foregroundStyle(.black)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.gray.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                HStack(spacing: 12) {
                    Picker("Month", selection: monthBinding) {
                        ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                            Text(month).tag(index + 1)
                        }
                    }
                    .frame(width: 150)

                    Picker("Year", selection: yearBinding) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .frame(width: 105)
                }
                .pickerStyle(.menu)
                .padding(16)
            }
        }
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: date) },
            set: { update(month: $0, year: calendar.component(.year, from: date)) }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: date) },
            set: { update(month: calendar.component(.month, from: date), year: $0) }
        )
    }

    private func update(month: Int, year: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let updated = calendar.date(from: components) {
            date = updated
        }
    }
}
