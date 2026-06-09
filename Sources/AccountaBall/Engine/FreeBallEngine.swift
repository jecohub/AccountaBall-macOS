import Foundation
import SwiftData
import AppKit

/// Passive observation mode. Captures full screen text every cycle, dedups
/// consecutive near-identical reads, and stores everything. Runs NO AI until
/// end(), which assembles the transcript + past recaps and makes one
/// summarizeFreeBall call.
@MainActor
final class FreeBallEngine {
    private let state: AppState
    private let captureService: ScreenCaptureService
    private let ocrService: OCRService
    private let aiService: AIService
    private var captureTask: Task<Void, Never>?
    private var appNapToken: NSObjectProtocol?

    var modelContext: ModelContext?
    private(set) var currentSession: FreeBallSession?

    /// Injectable clock (tests extend ranges without sleeping).
    var now: () -> Date = { Date() }

    init(state: AppState, captureService: ScreenCaptureService,
         ocrService: OCRService, aiService: AIService) {
        self.state = state
        self.captureService = captureService
        self.ocrService = ocrService
        self.aiService = aiService
    }

    // MARK: - lifecycle

    /// Start a session: create the record, set phase/start time, prevent App Nap,
    /// and start the silent capture loop.
    func begin() {
        beginSessionRecord()
        if appNapToken == nil {
            appNapToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "AccountaBall FreeBall session")
        }
        captureTask = captureService.startLoop(interval: AppConstants.cycleSeconds, panelTitle: "AccountaBall") { [weak self] frame in
            guard let self else { return }
            let text = await buildScreenText(from: frame, ocr: self.ocrService)
            guard !text.isEmpty else { return }
            await self.ingest(text: text)
        }
    }

    /// Test seam: set up a session without starting the real capture loop.
    func beginForTest() { beginSessionRecord() }

    private func beginSessionRecord() {
        guard let ctx = modelContext else { return }
        let session = FreeBallSession(startedAt: now())
        ctx.insert(session)
        try? ctx.save()
        currentSession = session
        state.freeBallStartTime = session.startedAt
        state.freeBallRecap = nil
        state.appPhase = .freeBall
    }

    /// Ingest one OCR read: extend the last block if it's the same screen, else
    /// open a new block. Never calls the AI.
    func ingest(text: String) {
        guard let session = currentSession, let ctx = modelContext else { return }
        session.cycleCount += 1
        if let last = session.captures.max(by: { $0.lastSeenAt < $1.lastSeenAt }),
           FreeBallDedup.isSameScreen(last.text, text) {
            last.lastSeenAt = now()
        } else {
            let cap = FreeBallCapture(firstSeenAt: now(), lastSeenAt: now(), text: text)
            ctx.insert(cap)
            session.captures.append(cap)
        }
        try? ctx.save()
    }

    /// Internal stop: cancel the loop and release the App Nap token.
    private func stop() {
        captureTask?.cancel(); captureTask = nil
        if let t = appNapToken { ProcessInfo.processInfo.endActivity(t); appNapToken = nil }
    }

    /// End the session: stop capturing, show the recap with a loading state, then
    /// make the single AI summarize call. Degrades gracefully if the AI is down.
    func end() async {
        stop()
        guard let session = currentSession, let ctx = modelContext else { return }
        session.endedAt = now()
        let duration = session.endedAt!.timeIntervalSince(session.startedAt)

        state.freeBallSummarizing = true
        state.appPhase = .freeBallRecap

        // Assemble transcript (chronological), condensed to the model's budget.
        let entries = session.captures
            .sorted { $0.firstSeenAt < $1.firstSeenAt }
            .map { FreeBallTranscriptEntry(text: $0.text, seconds: max($0.seconds, AppConstants.cycleSeconds)) }
        let totalChars = entries.reduce(0) { $0 + $1.text.count }

        // Trivial session: skip the AI, show a gentle recap.
        if totalChars < AppConstants.freeBallMinCharsToSummarize {
            session.narrative = "Not enough captured to summarize yet."
            try? ctx.save()
            publishRecap(date: session.startedAt, duration: duration, summary:
                FreeBallSummary(narrative: session.narrative, categories: [], insight: "",
                                workingOn: [], people: [], codeContext: [], openThreads: []),
                pending: false)
            finishEnd()
            return
        }

        let condensed = FreeBallCondenser.condense(entries)
        let pastRecaps = fetchPastRecaps(before: session)

        do {
            let summary = try await aiService.summarizeFreeBall(transcript: condensed, pastRecaps: pastRecaps)
            session.narrative = summary.narrative
            session.categories = summary.categories
            session.insight = summary.insight
            session.workingOn = summary.workingOn
            session.people = summary.people
            session.codeContext = summary.codeContext
            session.openThreads = summary.openThreads
            session.recapPending = false
            try? ctx.save()
            publishRecap(date: session.startedAt, duration: duration, summary: summary, pending: false)
        } catch {
            dbg("summarizeFreeBall failed: \(error)")
            session.recapPending = true     // keep raw captures for a later pass
            try? ctx.save()
            state.setupHint = "Couldn't summarize this FreeBall session — the AI was unreachable. Your capture was saved."
            publishRecap(date: session.startedAt, duration: duration,
                summary: FreeBallSummary(narrative: "", categories: [], insight: "", workingOn: [], people: [], codeContext: [], openThreads: []),
                pending: true)
        }
        finishEnd()
    }

    private func finishEnd() {
        state.freeBallSummarizing = false
        currentSession = nil
    }

    private func publishRecap(date: Date, duration: TimeInterval, summary: FreeBallSummary, pending: Bool) {
        state.freeBallRecap = FreeBallRecap(
            date: date, duration: duration, narrative: summary.narrative,
            categories: summary.categories, insight: summary.insight,
            workingOn: summary.workingOn, people: summary.people,
            codeContext: summary.codeContext, openThreads: summary.openThreads, recapPending: pending)
    }

    /// Most recent completed recaps (excluding this session), capped, as cross-session context.
    private func fetchPastRecaps(before session: FreeBallSession) -> [FreeBallPastRecap] {
        guard let ctx = modelContext else { return [] }
        let all = (try? ctx.fetch(FetchDescriptor<FreeBallSession>())) ?? []
        return all
            .filter { $0.id != session.id && $0.endedAt != nil && !$0.recapPending && !$0.narrative.isEmpty }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .prefix(AppConstants.freeBallPastRecapCap)
            .map { FreeBallPastRecap(narrative: $0.narrative, categories: $0.categories, insight: $0.insight, openThreads: $0.openThreads) }
    }
}
