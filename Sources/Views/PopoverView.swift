import SwiftUI
import AppKit

// MARK: - PopoverView

struct PopoverView: View {
    let store: PRStore
    /// Number of repos configured (passed from GitMeterApp to avoid coupling to SettingsStore).
    let repoCount: Int

    @Environment(\.openSettings) private var openSettings

    // MARK: - Collapse state (Part 3)
    @AppStorage("sectionCollapsedPending")   private var collapsedPending: Bool = false
    @AppStorage("sectionCollapsedHandled")   private var collapsedHandled: Bool = false
    @AppStorage("sectionCollapsedCommented") private var collapsedCommented: Bool = true
    @AppStorage("sectionCollapsedMine")      private var collapsedMine: Bool = false

    var body: some View {
        if repoCount == 0 {
            emptyReposView
        } else {
            mainContent
        }
    }

    // MARK: - Empty state

    private var emptyReposView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Adicione um repositório nos Ajustes")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Abrir Ajustes") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Hidden Esc handler: closes the panel while it is key.
            Button("") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    viewerHeader
                    pendingSection
                    handledSection
                    commentedSection
                    mineSection
                    codeRabbitAggregates
                    if allSectionsEmpty {
                        Text("Nenhuma PR sua ou aguardando você")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
            .frame(height: min(max(estimatedScrollHeight, 60), 520))

            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: - Height estimate
    //
    // Row layout after Part 0 padding bump:
    //   avatar 24pt; two text lines (callout ~17 + caption2 ~13 + spacing 2 = 32)
    //   content height = max(24, 32) = 32
    //   vertical content padding: 8pt top + 8pt bottom = 16
    //   row total = 32 + 16 = 48; using 50 for safety.
    //
    // Section header: caption + vertical pads (top 10 + bottom 4) = ~28; using 30.
    // Mine chips row: caption2 capsules ~20 + bottom-pad 4 = 24; using 26.
    // Collapsed section: header only (30), rows/chips skipped.

    private var estimatedScrollHeight: CGFloat {
        let s = store.summary
        var h: CGFloat = 0

        // Viewer header
        if store.viewerLogin != nil { h += 24 }

        // Pending section
        if !s.pendingMyReview.isEmpty {
            h += 30
            if !collapsedPending {
                h += CGFloat(s.pendingMyReview.count) * 50
            }
        }

        // Handled section
        if !s.handledByMe.isEmpty {
            h += 30
            if !collapsedHandled {
                h += CGFloat(s.handledByMe.count) * 50
            }
        }

        // Commented section (default collapsed)
        if !s.commentedByMe.isEmpty {
            h += 30
            if !collapsedCommented {
                h += CGFloat(s.commentedByMe.count) * 50
            }
        }

        // Mine section
        if !s.mine.isEmpty {
            h += 30
            if !collapsedMine {
                h += 26                         // chips row
                h += CGFloat(s.mine.count) * 50
            }
        }

        // CodeRabbit aggregates (always visible — independent of collapse)
        let crStats = store.codeRabbitStats.filter { $0.value.total > 0 }
        if !crStats.isEmpty {
            h += 1                              // Divider
            h += CGFloat(crStats.count) * 22
        }

        // All-empty placeholder
        if allSectionsEmpty { h += 60 }

        return h + 12                           // safety pad
    }

    private var allSectionsEmpty: Bool {
        store.summary.pendingMyReview.isEmpty
            && store.summary.handledByMe.isEmpty
            && store.summary.commentedByMe.isEmpty
            && store.summary.mine.isEmpty
    }

    // MARK: - Viewer header

    @ViewBuilder
    private var viewerHeader: some View {
        if let login = store.viewerLogin {
            HStack {
                Spacer()
                Text("@\(login)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var pendingSection: some View {
        let prs = store.summary.pendingMyReview
        if !prs.isEmpty {
            collapsibleHeader("Aguardando minha review", count: prs.count, collapsed: $collapsedPending)
            if !collapsedPending {
                ForEach(prs) { pr in
                    PRRowView(pr: pr, bucket: .pendingMyReview, viewerLogin: store.viewerLogin)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var handledSection: some View {
        let prs = store.summary.handledByMe
        if !prs.isEmpty {
            collapsibleHeader("Respondidas por mim", count: prs.count, collapsed: $collapsedHandled)
            if !collapsedHandled {
                ForEach(prs) { pr in
                    PRRowView(pr: pr, bucket: .handledByMe, viewerLogin: store.viewerLogin)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var commentedSection: some View {
        let prs = store.summary.commentedByMe
        if !prs.isEmpty {
            collapsibleHeader("Comentadas por mim", count: prs.count, collapsed: $collapsedCommented)
            if !collapsedCommented {
                ForEach(prs) { pr in
                    PRRowView(pr: pr, bucket: .commentedByMe, viewerLogin: store.viewerLogin)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var mineSection: some View {
        let prs = store.summary.mine
        if !prs.isEmpty {
            let s = store.summary
            collapsibleHeader("Minhas PRs", count: prs.count, collapsed: $collapsedMine)
            if !collapsedMine {
                mineChips(s)
                ForEach(prs) { pr in
                    PRRowView(pr: pr, bucket: .mine, viewerLogin: store.viewerLogin)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func mineChips(_ s: Summary) -> some View {
        let chips: [(String, Color, Color)] = [
            ("\(s.mineApproved) aprovadas",   .green,   Color.green.opacity(0.15)),
            ("\(s.mineChangesRequested) alterações", .orange, Color.orange.opacity(0.15)),
            ("\(s.mineAwaiting) aguardando",  Color.primary, Color.primary.opacity(0.08)),
            ("\(s.mineDrafts) rascunhos",     Color.secondary, Color.primary.opacity(0.05)),
        ]
        let counts = [s.mineApproved, s.mineChangesRequested, s.mineAwaiting, s.mineDrafts]
        let visible = zip(chips, counts).filter { $0.1 > 0 }.map(\.0)

        if !visible.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, chip in
                    Text(chip.0)
                        .font(.caption2)
                        .foregroundStyle(chip.1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(chip.2)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: - CodeRabbit aggregates

    @ViewBuilder
    private var codeRabbitAggregates: some View {
        let stats = store.codeRabbitStats.filter { $0.value.total > 0 }
        if !stats.isEmpty {
            Divider()
            ForEach(Array(stats.keys.sorted()), id: \.self) { repoId in
                if let stat = stats[repoId] {
                    HStack(spacing: 4) {
                        Image(systemName: "hare.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("CodeRabbit: \(stat.touched)/\(stat.total) PRs — \(repoId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            refreshControl

            Text(lastUpdatedText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !store.cappedRepos.isEmpty {
                Text(capText)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !store.repoErrors.isEmpty {
                let tooltip = store.repoErrors.sorted(by: { $0.key < $1.key })
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .help(tooltip)
            }

            Spacer()

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Ajustes")

            Button("Sair") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var refreshControl: some View {
        if store.isRefreshing {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        } else {
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Atualizar agora")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - Helpers

    /// Collapsible section header: full-width click target, leading chevron.
    private func collapsibleHeader(_ title: String, count: Int, collapsed: Binding<Bool>) -> some View {
        Button {
            collapsed.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(title) (\(count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lastUpdatedText: String {
        guard let date = store.lastUpdated else { return "—" }
        if Date.now.timeIntervalSince(date) < 60 {
            return "Atualizado agora"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return "Atualizado \(formatter.localizedString(for: date, relativeTo: .now))"
    }

    /// Cap warning text: single repo → "Mostrando 50 de N";
    /// multiple capped repos → per-repo breakdown joined by comma.
    private var capText: String {
        let capped = store.cappedRepos.sorted { $0.key < $1.key }
        if capped.count == 1, let entry = capped.first {
            return "Mostrando 50 de \(entry.value)"
        }
        return capped.map { "\($0.key): 50/\($0.value)" }.joined(separator: ", ")
    }
}

// MARK: - PRRowView

struct PRRowView: View {
    let pr: PullRequest
    let bucket: RowBucket
    let viewerLogin: String?

    @State private var isHovered = false

    enum RowBucket {
        case pendingMyReview, handledByMe, commentedByMe, mine
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            rowContent
        }
        .buttonStyle(HighlightButtonStyle(isHovered: isHovered))
        .onHover { hovering in isHovered = hovering }
        .help(pr.authorLogin)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            Button("Abrir no navegador") {
                NSWorkspace.shared.open(pr.url)
            }
            Button("Copiar URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            }
            Button("Copiar branch") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.headRefName, forType: .string)
            }
            .disabled(pr.headRefName.isEmpty)
            Button("Abrir arquivos alterados") {
                if let filesURL = URL(string: pr.url.absoluteString + "/files") {
                    NSWorkspace.shared.open(filesURL)
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = ["PR #\(pr.number) por \(pr.authorLogin): \(pr.title)"]
        if let ci = pr.ciState {
            switch ci {
            case .success: parts.append("CI: passou")
            case .failure: parts.append("CI: falhou")
            case .pending: parts.append("CI: rodando")
            }
        }
        if pr.mergeableState == .conflicting { parts.append("conflito de merge") }
        if !pr.codeRabbitTouched && !pr.isDraft { parts.append("sem revisão CodeRabbit") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Row content (Part 0: padding ≥10pt horizontal, ≥8pt vertical inside highlight)

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            avatarView
                .frame(width: 24, height: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                secondaryLine
            }

            Spacer(minLength: 0)

            Text(compactRelativeTime(from: pr.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        // Part 0: ≥10pt horizontal, ≥8pt vertical content padding inside the highlight rect
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                .padding(.horizontal, 6)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Avatar

    private var avatarView: some View {
        AsyncImage(url: URL(string: "https://avatars.githubusercontent.com/\(pr.authorLogin)?s=48")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            default:
                avatarPlaceholder
            }
        }
        .frame(width: 24, height: 24)
    }

    private var avatarPlaceholder: some View {
        let initial = pr.authorLogin.first.map { String($0).uppercased() } ?? "?"
        let colors: [Color] = [
            Color(red: 0.40, green: 0.55, blue: 0.75),
            Color(red: 0.55, green: 0.40, blue: 0.75),
            Color(red: 0.40, green: 0.65, blue: 0.55),
            Color(red: 0.70, green: 0.50, blue: 0.35),
            Color(red: 0.65, green: 0.40, blue: 0.45),
            Color(red: 0.40, green: 0.55, blue: 0.65),
        ]
        let index = pr.authorLogin.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count
        return ZStack {
            Circle().fill(colors[index])
            Text(initial)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Row lines

    private var titleLine: some View {
        HStack(spacing: 4) {
            Text("#\(pr.number)")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(pr.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.callout)
        }
    }

    /// Meta line: [status icon] [CI icon] [+adds −dels] [thread chips] [conflict chip] [sem-CodeRabbit chip] [draft tag] [equipe hint]
    /// Single non-wrapping HStack to preserve row height determinism.
    private var secondaryLine: some View {
        HStack(spacing: 4) {
            statusIcon
                .font(.caption2)

            ciIcon

            diffStats

            threadsBadge

            conflictChip

            codeRabbitAbsentChip

            if pr.isDraft {
                draftTag
            }

            if !pr.requestedTeamSlugs.isEmpty,
               let viewer = viewerLogin,
               !pr.requestedUserLogins.contains(viewer) {
                Text("equipe")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Status icon

    @ViewBuilder
    private var statusIcon: some View {
        switch bucket {
        case .pendingMyReview:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)

        case .handledByMe:
            handledIcon

        case .commentedByMe:
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)

        case .mine:
            mineIcon
        }
    }

    @ViewBuilder
    private var handledIcon: some View {
        let state = viewerLogin.flatMap { pr.latestReviewByAuthor[$0] }
        switch state {
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .changesRequested:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mineIcon: some View {
        if pr.isDraft {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(.secondary)
        } else {
            switch effectiveDecision(pr) {
            case .approved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .changesRequested:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            default:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - CI icon (Part 2)

    @ViewBuilder
    private var ciIcon: some View {
        if let ci = pr.ciState {
            switch ci {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help("CI: passou")
            case .failure:
                Image(systemName: "x.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help("CI: falhou")
            case .pending:
                Image(systemName: "clock.badge")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("CI: rodando")
            }
        }
    }

    // MARK: - Diff stats (Part 2)

    @ViewBuilder
    private var diffStats: some View {
        if pr.additions > 0 || pr.deletions > 0 {
            Text("+\(pr.additions)")
                .font(.caption2)
                .foregroundStyle(.green)
            Text("−\(pr.deletions)")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Threads badge

    @ViewBuilder
    private var threadsBadge: some View {
        let cappedSuffix = pr.threadsCapped ? "+" : ""
        if pr.threadsUnresolvedFetched > 0 {
            Text("\(pr.threadsUnresolvedFetched)\(cappedSuffix) abertas")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
        if pr.threadsResolvedFetched > 0 {
            Text("\(pr.threadsResolvedFetched)\(cappedSuffix) resolvidas")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Conflict chip (Part 2)

    @ViewBuilder
    private var conflictChip: some View {
        if pr.mergeableState == .conflicting {
            Text("conflito")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - Sem CodeRabbit chip (Part 2: replaces hare.fill badge)

    @ViewBuilder
    private var codeRabbitAbsentChip: some View {
        if !pr.codeRabbitTouched && !pr.isDraft {
            Text("sem CodeRabbit")
                .font(.caption2)
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - Draft tag

    private var draftTag: some View {
        Text("Rascunho")
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }
}

// MARK: - HighlightButtonStyle

struct HighlightButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
    }
}

// MARK: - Relative time helper

/// Stable, locale-independent compact relative time. Uses unicode-scalar sum for determinism.
func compactRelativeTime(from date: Date, to now: Date = .now) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    guard seconds >= 0 else { return "agora" }
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24
    if seconds < 60 { return "agora" }
    if minutes < 60 { return "há \(minutes)min" }
    if hours < 24   { return "há \(hours)h" }
    return "há \(days)d"
}
