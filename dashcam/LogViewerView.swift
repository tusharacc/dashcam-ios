//
//  LogViewerView.swift
//  dashcam
//
//  In-app log viewer and analysis interface
//

import SwiftUI
import UniformTypeIdentifiers

struct LogViewerView: View {
    @State private var logs: [String] = []
    @State private var filteredLogs: [String] = []
    @State private var searchText = ""
    @State private var selectedLogLevel = "ALL"
    @State private var isLoading = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    private let observability = ObservabilityService.shared
    private let logLevels = ["ALL", "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and filter controls
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)

                        TextField("Search logs...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchText) { _ in
                                filterLogs()
                            }

                        if !searchText.isEmpty {
                            Button("Clear") {
                                searchText = ""
                            }
                            .foregroundColor(.blue)
                        }
                    }

                    // Filter controls
                    HStack {
                        Text("Level:")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Picker("Log Level", selection: $selectedLogLevel) {
                            ForEach(logLevels, id: \.self) { level in
                                Text(level)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: selectedLogLevel) { _ in
                            filterLogs()
                        }

                        Spacer()

                        // Export button
                        Button(action: exportLogs) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))

                Divider()

                // Log list
                if isLoading {
                    Spacer()
                    ProgressView("Loading logs...")
                    Spacer()
                } else if filteredLogs.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.gray)

                        Text(logs.isEmpty ? "No logs available" : "No logs match your search")
                            .font(.headline)
                            .foregroundColor(.gray)

                        if !logs.isEmpty && !searchText.isEmpty {
                            Button("Clear Search") {
                                searchText = ""
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, logLine in
                            LogEntryRow(logLine: logLine, index: logs.count - filteredLogs.count + index)
                        }
                    }
                    .listStyle(PlainListStyle())
                }

                // Stats bar
                HStack {
                    Text("\(filteredLogs.count) of \(logs.count) entries")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    Button("Refresh") {
                        loadLogs()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadLogs()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let exportURL = exportURL {
                    ActivityViewController(activityItems: [exportURL])
                }
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage)
            }
        }
    }

    private func loadLogs() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let loadedLogs = observability.getLocalLogs(limit: 2000)

            DispatchQueue.main.async {
                self.logs = loadedLogs.reversed() // Show newest first
                self.filterLogs()
                self.isLoading = false
            }
        }
    }

    private func filterLogs() {
        var filtered = logs

        // Apply level filter
        if selectedLogLevel != "ALL" {
            filtered = filtered.filter { $0.contains("[\(selectedLogLevel)]") }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.lowercased().contains(searchText.lowercased()) }
        }

        filteredLogs = filtered
    }

    private func exportLogs() {
        print("🔵 Export button tapped")
        observability.info("LogViewer", "Exporting logs")

        DispatchQueue.global(qos: .userInitiated).async {
            print("🔵 Calling observability.exportLogs()")
            if let exportURL = observability.exportLogs() {
                print("✅ Export successful: \(exportURL)")
                DispatchQueue.main.async {
                    self.exportURL = exportURL
                    self.showingExportSheet = true
                    print("✅ Showing export sheet")
                }
            } else {
                print("❌ Export failed - exportURL is nil")
                DispatchQueue.main.async {
                    self.exportErrorMessage = "Failed to export logs. No log files found."
                    self.showExportError = true
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let logLine: String
    let index: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Line number
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 40, alignment: .leading)

                // Log level indicator
                if let level = extractLogLevel(from: logLine) {
                    LogLevelBadge(level: level)
                }

                // Timestamp and category
                VStack(alignment: .leading, spacing: 2) {
                    if let (timestamp, category) = extractTimestampAndCategory(from: logLine) {
                        HStack {
                            Text(formatTimestamp(timestamp))
                                .font(.caption)
                                .foregroundColor(.blue)

                            Text(category)
                                .font(.caption)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    // Message (truncated or full)
                    let message = extractMessage(from: logLine)
                    Text(isExpanded ? message : String(message.prefix(100)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 2)

                    if message.count > 100 {
                        Button(isExpanded ? "Show Less" : "Show More") {
                            isExpanded.toggle()
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if extractMessage(from: logLine).count > 100 {
                isExpanded.toggle()
            }
        }
    }

    private func extractLogLevel(from logLine: String) -> String? {
        let pattern = #"\[([A-Z]+)\]"#
        if let range = logLine.range(of: pattern, options: .regularExpression) {
            let match = String(logLine[range])
            return match.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return nil
    }

    private func extractTimestampAndCategory(from logLine: String) -> (String, String)? {
        // Extract timestamp and category using regex
        let pattern = #"\[(.*?)\].*?\[(.*?)\].*?\[(.*?)\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: logLine.utf16.count)

        if let match = regex?.firstMatch(in: logLine, options: [], range: range) {
            let timestampRange = Range(match.range(at: 1), in: logLine)
            let categoryRange = Range(match.range(at: 3), in: logLine)

            if let timestampRange = timestampRange, let categoryRange = categoryRange {
                return (String(logLine[timestampRange]), String(logLine[categoryRange]))
            }
        }

        return nil
    }

    private func extractMessage(from logLine: String) -> String {
        // Extract message after the third closing bracket
        let components = logLine.components(separatedBy: "] ")
        if components.count >= 4 {
            return components.dropFirst(3).joined(separator: "] ")
        }
        return logLine
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        // Convert ISO8601 to readable format
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm:ss"
            return displayFormatter.string(from: date)
        }
        return timestamp
    }
}

struct LogLevelBadge: View {
    let level: String

    private var color: Color {
        switch level {
        case "DEBUG": return .gray
        case "INFO": return .blue
        case "WARNING": return .orange
        case "ERROR": return .red
        case "CRITICAL": return .purple
        default: return .gray
        }
    }

    var body: some View {
        Text(level)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
}

// Activity View Controller for sharing logs
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Log Analytics View
struct LogAnalyticsView: View {
    @State private var analytics = LogAnalytics()
    @State private var isLoading = true

    private let observability = ObservabilityService.shared

    struct LogAnalytics {
        var totalLogs = 0
        var errorCount = 0
        var warningCount = 0
        var criticalCount = 0
        var categoriesCount: [String: Int] = [:]
        var recentErrors: [String] = []

        var errorRate: Double {
            totalLogs > 0 ? Double(errorCount) / Double(totalLogs) : 0
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if isLoading {
                        ProgressView("Analyzing logs...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Summary cards
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            AnalyticsCard(title: "Total Logs", value: "\(analytics.totalLogs)", color: .blue)
                            AnalyticsCard(title: "Error Rate", value: "\(Int(analytics.errorRate * 100))%", color: analytics.errorRate > 0.05 ? .red : .green)
                            AnalyticsCard(title: "Warnings", value: "\(analytics.warningCount)", color: .orange)
                            AnalyticsCard(title: "Critical", value: "\(analytics.criticalCount)", color: .purple)
                        }

                        // Categories breakdown
                        if !analytics.categoriesCount.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Categories")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(Array(analytics.categoriesCount.sorted { $0.value > $1.value }), id: \.key) { category, count in
                                    HStack {
                                        Text(category)
                                            .font(.body)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.body)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)
                        }

                        // Recent errors
                        if !analytics.recentErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent Errors")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(Array(analytics.recentErrors.prefix(10)), id: \.self) { error in
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Log Analytics")
            .onAppear {
                analyzeLog()
            }
            .refreshable {
                analyzeLog()
            }
        }
    }

    private func analyzeLog() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let logs = observability.getLocalLogs(limit: 5000)
            var newAnalytics = LogAnalytics()

            newAnalytics.totalLogs = logs.count

            for log in logs {
                // Count by level
                if log.contains("[ERROR]") {
                    newAnalytics.errorCount += 1
                    newAnalytics.recentErrors.append(log)
                } else if log.contains("[WARNING]") {
                    newAnalytics.warningCount += 1
                } else if log.contains("[CRITICAL]") {
                    newAnalytics.criticalCount += 1
                    newAnalytics.recentErrors.append(log)
                }

                // Count by category
                if let category = extractCategory(from: log) {
                    newAnalytics.categoriesCount[category, default: 0] += 1
                }
            }

            DispatchQueue.main.async {
                self.analytics = newAnalytics
                self.isLoading = false
            }
        }
    }

    private func extractCategory(from logLine: String) -> String? {
        let pattern = #"\[.*?\]\s*\[.*?\]\s*\[(.*?)\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: logLine.utf16.count)

        if let match = regex?.firstMatch(in: logLine, options: [], range: range),
           let categoryRange = Range(match.range(at: 1), in: logLine) {
            return String(logLine[categoryRange])
        }

        return nil
    }
}

struct AnalyticsCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}