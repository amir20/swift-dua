import FoundationModels

/// A short, on-device summary of a scanned folder, produced by Apple's
/// Foundation Models framework with guided generation. Two fields so the rail
/// can render a headline and a separate, actionable reclaim line.
@Generable
struct SpaceInsight: Equatable, Sendable {
    @Guide(
        description:
            "One friendly, specific sentence (max 28 words) describing what is using the most space in this folder. Name the largest folders or file types. Use only the figures provided — never invent numbers."
    )
    var headline: String

    @Guide(
        description:
            "One short, practical sentence about what is safe to clear to free space. If nothing is flagged reclaimable, say space looks well used instead of inventing cleanup advice."
    )
    var tip: String
}

/// Lifecycle of the rail's scope overview. There is no user-facing failure or
/// "unavailable" surface by design: when a summary can't be produced, the rail
/// simply shows nothing, so the feature is invisible until it has something to
/// say.
enum SummaryState: Equatable {
    case idle
    case loading
    case ready(SpaceInsight)
}

/// Thin wrapper over the on-device system language model. Stateless: a fresh
/// session per request, since each summary is a one-shot over independent scan
/// facts.
@MainActor
enum SummaryService {
    /// Whether the on-device model is ready to run right now. Everything else
    /// about model availability is deliberately hidden from the UI.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
        You write a brief disk-usage summary for Halo, a macOS app that visualizes \
        what is taking up space in a folder. You are given a plain list of the \
        folder's largest items with their sizes, and how much is safely reclaimable. \
        Be concise, concrete, and friendly — like a knowledgeable colleague. Refer \
        only to the figures and names provided; do not invent files, sizes, or paths. \
        Keep each field to a single sentence.
        """

    /// Generate a summary from a pre-formatted facts block (see
    /// `ScanModel.summaryFacts`). Throws if the model errors or is unavailable.
    static func summarize(_ facts: String) async throws -> SpaceInsight {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: facts,
            generating: SpaceInsight.self,
            options: GenerationOptions(temperature: 0.4))
        return response.content
    }
}
