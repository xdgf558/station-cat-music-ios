import SwiftUI
import UIKit

/// The editor retains the epoch and scope that the user actually opened.
struct PlatformNotebookEditorContext: Identifiable {
    let id = UUID()
    let note: NotebookNote?
    let work: NotebookWork?
    let quote: String?
    let topicID: UUID?
    let epoch: UUID
    let scope: AccountScope

    init(note: NotebookNote? = nil, work: NotebookWork? = nil, quote: String? = nil,
         state: NotebookState, scope: AccountScope, topicID: UUID? = nil) {
        self.note = note; self.work = note?.work ?? work; self.quote = note?.quote ?? quote
        self.topicID = note?.topicID ?? topicID; self.epoch = state.epoch; self.scope = scope
    }
}

struct PlatformNotebookPage: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var editor: PlatformNotebookEditorContext?
    @State private var topics: PlatformNotebookEditorContext?
    @State private var pendingWork: NotebookWork?
    private enum Filter: Equatable { case all, uncategorized, topic(UUID) }

    private var notes: [NotebookNote] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (model.notebookState?.notes ?? []).filter { note in
            guard belongs(note, to: filter) else { return false }
            guard !text.isEmpty else { return true }
            let workTitle = model.notebookTrack(for: note.work)?.title ?? model.notebookBookmark(for: note.work)?.title ?? ""
            let topic = model.notebookState?.topics.first(where: { $0.id == note.topicID })?.name ?? ""
            return [note.title, note.body, note.quote ?? "", topic, workTitle].contains { $0.localizedStandardContains(text) }
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    private func belongs(_ note: NotebookNote, to category: Filter) -> Bool {
        switch category {
        case .all: true
        case .uncategorized: note.topicID == nil
        case .topic(let id): note.topicID == id
        }
    }
    private func count(_ category: Filter) -> Int {
        (model.notebookState?.notes ?? []).filter { belongs($0, to: category) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("NOTEBOOK").radioMono(10, weight: .semibold).tracking(2).foregroundStyle(Palette.muted)
                    Text(model.t("notebookTitle")).radioSerif(34, weight: .black, relativeTo: .largeTitle)
                        .padding(.vertical, -5)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("notebookPage")
                    Text(model.t("radio.notebookIntro")).font(.subheadline).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(5)
                }
                search
                filters
                if let state = model.notebookState {
                    if notes.isEmpty { empty(state.notes.isEmpty) }
                    else {
                        LazyVStack(spacing: 14) {
                            ForEach(notes, id: \.id) { note in
                                Button { editor = .init(note: note, state: state, scope: model.scope) } label: {
                                    PlatformNotebookRow(model: model, note: note)
                                }.buttonStyle(.plain).accessibilityIdentifier("notebook.note." + note.id.uuidString)
                            }
                        }
                    }
                } else if model.notebookErrorKey == nil {
                    ProgressView(model.t("notebookLoading")).frame(maxWidth: .infinity, minHeight: 160)
                }
                if model.notebookErrorKey != nil { NotebookFailure(model: model, retry: { Task { await model.refreshNotebook() } }) }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Palette.background).foregroundStyle(Palette.ink)
            .navigationTitle("").toolbar(.hidden, for: .navigationBar).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.selectedTab == 2 { notebookActions }
            }
            .task { await model.refreshNotebook(); openRequestedNote() }
            .fullScreenCover(item: $editor, onDismiss: openPendingWork) { context in
                PlatformNotebookEditor(model: model, context: context, onSaved: {
                    model.selectedTab = 2; model.showRadioToast(model.t("radio.noteSaved"))
                }) { pendingWork = $0 }
            }
            .sheet(item: $topics) { context in PlatformNotebookTopics(model: model, context: context) }
            .onChange(of: model.notebookState?.topics.map(\.id)) { _, ids in
                if case .topic(let id) = filter, !(ids ?? []).contains(id) { filter = .all }
            }
            .onChange(of: model.radioNoteID) { _, _ in openRequestedNote() }
            .onChange(of: model.selectedTab) { _, _ in openRequestedNote() }
            .onChange(of: model.notebookState?.revision) { _, _ in openRequestedNote() }
    }
    private var notebookActions: some View {
        HStack {
            Spacer()
            Button {
                guard let state = model.notebookState else { return }
                let selectedTopic: UUID?
                if case .topic(let id) = filter { selectedTopic = id } else { selectedTopic = nil }
                editor = .init(state: state, scope: model.scope, topicID: selectedTopic)
            } label: {
                Label(model.t("radio.writePage"), systemImage: "plus")
                    .font(.body.weight(.bold)).padding(.horizontal, 21).frame(minHeight: 50)
                    .foregroundStyle(.white).background(Palette.accent, in: Capsule())
                    .shadow(color: Palette.accent.opacity(0.2), radius: 10, y: 6)
            }.buttonStyle(.plain).accessibilityIdentifier("notebookNew")
                .disabled(model.notebookState == nil || model.notebookBusy)
        }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    }
    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
            TextField(model.t("notebookSearch"), text: $query).textInputAutocapitalization(.never)
                .autocorrectionDisabled().accessibilityIdentifier("notebookSearch")
        }.padding(.horizontal, 15).frame(minHeight: 46)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
    private var filters: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    chip(model.t("notebookAll"), filter: .all, id: "all")
                    ForEach(model.notebookState?.topics ?? [], id: \.id) { topic in
                        chip(topic.name, filter: .topic(topic.id), id: topic.id.uuidString)
                    }
                    chip(model.t("notebookUncategorized"), filter: .uncategorized, id: "uncategorized")
                }
            }
            Button {
                guard let state = model.notebookState else { return }
                topics = .init(state: state, scope: model.scope)
            } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel(model.t("notebookManageTopics"))
                .accessibilityIdentifier("notebookManageTopics")
                .disabled(model.notebookState == nil || model.notebookBusy)
        }.overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 1) }
    }
    private func chip(_ title: String, filter value: Filter, id: String) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(count(value).formatted()).radioMono(11).opacity(0.7)
            }.fixedSize().padding(.horizontal, 15).frame(minHeight: 44)
                .foregroundStyle(filter == value ? Palette.background : Palette.muted)
                .background(filter == value ? Palette.ink : .clear,
                            in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier("notebook.filter." + id).accessibilityLabel(title)
            .accessibilityValue(count(value).formatted())
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
    private func empty(_ noNotes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("radio.notebookEmpty")).radioSerif(22)
            Text(model.t(noNotes ? "notebookEmptyDetail" : "notebookNoResultsDetail"))
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
        }.padding(.vertical, 28).frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            .accessibilityIdentifier("notebookEmpty")
    }
    private func openRequestedNote() {
        guard model.selectedTab == 2, let id = model.radioNoteID, let state = model.notebookState else { return }
        model.radioNoteID = nil
        guard let note = state.notes.first(where: { $0.id == id }) else { return }
        editor = .init(note: note, state: state, scope: model.scope)
    }
    private func openPendingWork() {
        guard let work = pendingWork else { return }
        pendingWork = nil; model.openNotebookWork(work)
    }
}

struct PlatformNotebookRow: View {
    let model: AppModel
    let note: NotebookNote
    @Environment(\.dynamicTypeSize) private var typeSize
    private var track: Track? { model.notebookTrack(for: note.work) }
    private var workTitle: String { track?.title ?? model.notebookBookmark(for: note.work)?.title ?? model.t("notebookWorkUnavailable") }
    private var title: String { note.title.isEmpty ? model.t("notebookUntitled") : note.title }
    private var topic: String { model.notebookState?.topics.first(where: { $0.id == note.topicID })?.name ?? model.t("notebookUncategorized") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.updatedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: model.locale))) + " · " + topic)
                .radioMono(11).foregroundStyle(Palette.muted)
            Text(title).radioSerif(18).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if let quote = note.quote {
                Text("「" + quote + "」").radioSerif(15, weight: .medium).foregroundStyle(Palette.accent)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            if !note.body.isEmpty {
                Text(note.body).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
            }
            if note.work != nil {
                HStack(spacing: 9) {
                    if let track {
                        OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "music.note").frame(width: 24, height: 24).foregroundStyle(Palette.muted)
                    }
                    Text(model.t("radio.noteLinked") + " · " + workTitle).font(.caption).foregroundStyle(Palette.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }.padding(.top, 3)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }
}

struct PlatformNotebookEditor: View {
    @Bindable var model: AppModel
    let context: PlatformNotebookEditorContext
    var onSaved: (() -> Void)?
    var openWork: (NotebookWork) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var title: String
    @State private var bodyText: String
    @State private var topicID: UUID?
    @State private var work: NotebookWork?
    @State private var quote: String?
    @State private var showSongs = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var working = false
    @State private var failed = false
    @State private var draftID: UUID
    @State private var titleLineBreaksReplaced = false
    @State private var writingHelpExpanded = false
    @FocusState private var focusedField: EditorField?
    @ScaledMetric(relativeTo: .body) private var lineHeight = 32.0
    private enum EditorField: Hashable { case title, body }

    init(model: AppModel, context: PlatformNotebookEditorContext, onSaved: (() -> Void)? = nil,
         openWork: @escaping (NotebookWork) -> Void) {
        self.model = model; self.context = context; self.onSaved = onSaved; self.openWork = openWork
        _title = State(initialValue: context.note?.title ?? ""); _bodyText = State(initialValue: context.note?.body ?? "")
        _topicID = State(initialValue: context.topicID); _work = State(initialValue: context.work)
        _quote = State(initialValue: context.quote); _draftID = State(initialValue: context.note?.id ?? UUID())
    }
    private var dirty: Bool {
        title != (context.note?.title ?? "") || bodyText != (context.note?.body ?? "") ||
        topicID != context.topicID || work != context.work || quote != context.note?.quote
    }
    private var stale: Bool { model.scope != context.scope || model.notebookState?.epoch != context.epoch }
    private var busy: Bool { working || model.notebookBusy }
    private var hasText: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || quote != nil
    }
    private var workTitle: String { model.notebookTrack(for: work)?.title ?? model.notebookBookmark(for: work)?.title ?? model.t(work == nil ? "notebookNoWork" : "notebookWorkUnavailable") }
    private var singleLineTitle: Binding<String> {
        Binding(get: { title }, set: { value in
            let normalized = NotebookTitleInput.singleLine(value)
            if normalized != value { titleLineBreaksReplaced = true }
            title = normalized
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    editorTopics
                    TextField(model.t("radio.noteTitlePlaceholder"), text: singleLineTitle)
                        .radioSerif(26, weight: .black, relativeTo: .title).disabled(busy)
                        .accessibilityIdentifier("notebookTitleField").focused($focusedField, equals: .title)
                        .submitLabel(.next).onSubmit { focusedField = .body }
                    if titleLineBreaksReplaced {
                        Text(model.t("notebookTitleLineBreaksReplaced")).font(.footnote).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("notebookTitleLineBreaksReplaced")
                    }
                    associatedWork
                    if let quote {
                        HStack(alignment: .top, spacing: 14) {
                            Rectangle().fill(Palette.accent).frame(width: 2)
                            Text(quote).radioSerif(17, weight: .medium).foregroundStyle(Palette.accent)
                                .lineSpacing(8).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            Button { self.quote = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                                .accessibilityLabel(model.t("radio.removeQuote")).disabled(busy || stale)
                        }.fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("notebookQuote")
                    }
                    ZStack(alignment: .topLeading) {
                        NotebookPaperLines(spacing: lineHeight)
                        if bodyText.isEmpty {
                            Text(model.t("radio.noteBodyPlaceholder")).font(.body).foregroundStyle(Palette.muted)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true)
                        }
                        TextEditor(text: $bodyText).font(.body).lineSpacing(12).frame(minHeight: 440)
                            .scrollContentBackground(.hidden).disabled(busy).focused($focusedField, equals: .body)
                            .accessibilityLabel(model.t("notebookBody")).accessibilityIdentifier("notebookBodyField")
                    }
                    HStack {
                        Spacer()
                        Text("\(bodyText.count) / 8000 · " + model.t("radio.localOnly"))
                            .radioMono(11).foregroundStyle(bodyText.count > PlatformNotebookStore.maximumBodyLength ? Palette.accent : Palette.muted)
                    }
                    DisclosureGroup(isExpanded: $writingHelpExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.t("notebookTextLimits")).font(.caption).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("notebookTextLimits")
                            Text(model.t("radio.quotePrivacy")).font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 6)
                    } label: {
                        Text(model.t("radio.writingHelp")).font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("notebookWritingHelp")
                    }.tint(Palette.muted).accessibilityElement(children: .contain)
                    if let work {
                        Button(model.t("notebookOpenWork")) { openWork(work); dismiss() }
                            .frame(minHeight: 44).disabled(dirty || busy || stale).accessibilityIdentifier("notebookOpenWork")
                    }
                    if stale {
                        Label(model.t("notebookStaleDetail"), systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Palette.muted)
                    } else if failed { NotebookFailure(model: model) }
                    if context.note != nil {
                        Button(model.t("notebookDelete"), role: .destructive) { confirmDelete = true }
                            .frame(minHeight: 44).disabled(busy || stale).accessibilityIdentifier("notebookDelete")
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
                    .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Palette.background).foregroundStyle(Palette.ink).scrollDismissesKeyboard(.interactively)
                .toolbar(.hidden, for: .navigationBar).safeAreaInset(edge: .top, spacing: 0) { editorHeader }
                .sheet(isPresented: $showSongs) { PlatformNotebookSongPicker(model: model, selection: $work) }
                .onChange(of: work) { old, new in if old != new { quote = nil } }
                .alert(model.t("notebookDiscardConfirm"), isPresented: $confirmDiscard) {
                    Button(model.t("notebookDiscard"), role: .destructive) { dismiss() }
                    Button(model.t("notebookKeepEditing"), role: .cancel) {}
                }
                .alert(model.t("notebookDeleteConfirm"), isPresented: $confirmDelete) {
                    Button(model.t("notebookDelete"), role: .destructive) {
                        working = true; failed = false
                        Task {
                            let success = await model.removeNotebook(id: draftID, expectedEpoch: context.epoch, scope: context.scope)
                            working = false
                            if success { dismiss() } else { failed = true }
                        }
                    }
                    Button(model.t("cancel"), role: .cancel) {}
                } message: { Text(model.t("notebookDeleteDetail")) }
        }.tint(Palette.accent).interactiveDismissDisabled(dirty || busy).accessibilityIdentifier("notebookEditor")
            .overlay(alignment: .top) {
                if let message = model.radioToast {
                    Text(message).font(.subheadline).multilineTextAlignment(.center)
                        .foregroundStyle(Palette.darkText).padding(.horizontal, 20).padding(.vertical, 13)
                        .background(Palette.dark, in: Capsule()).padding(.horizontal, 20).padding(.top, 8)
                        .transition(.opacity).allowsHitTesting(false).accessibilityIdentifier("notebookToast")
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.radioToast)
            .onChange(of: model.radioToast) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
    }
    private var editorHeader: some View {
        HStack(spacing: 8) {
            Button(model.t("cancel")) { if dirty { confirmDiscard = true } else { dismiss() } }
                .font(.subheadline).foregroundStyle(Palette.muted).frame(minWidth: 44, minHeight: 44)
                .disabled(busy).accessibilityIdentifier("notebookEditorClose")
            Spacer(minLength: 4)
            Text(model.t(context.note == nil ? "radio.newPage" : "notebookEdit")).radioMono(11, weight: .semibold)
                .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Spacer(minLength: 4)
            Button(action: save) {
                Group { if working { ProgressView().tint(.white) } else { Text(model.t("notebookSave")) } }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44).background(Palette.accent, in: Capsule())
            }.buttonStyle(.plain).disabled(busy || stale).accessibilityIdentifier("notebookSave")
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Palette.background)
    }
    private var editorTopics: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.notebookState?.topics ?? [], id: \.id) { topic in editorTopic(topic.name, id: topic.id) }
                editorTopic(model.t("notebookUncategorized"), id: nil)
            }
        }.accessibilityIdentifier("notebookTopicPicker")
    }
    private func editorTopic(_ name: String, id: UUID?) -> some View {
        Button { topicID = id } label: {
            Text(name).font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(topicID == id ? Palette.background : Palette.ink)
                .background(topicID == id ? Palette.ink : .clear, in: Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: topicID == id ? 0 : 1))
        }.buttonStyle(.plain).disabled(busy || stale).accessibilityAddTraits(topicID == id ? .isSelected : [])
            .accessibilityIdentifier("notebook.editorTopic." + (id?.uuidString ?? "uncategorized")).accessibilityLabel(name)
    }
    private var associatedWork: some View {
        HStack(spacing: 12) {
            Button { showSongs = true } label: {
                HStack(spacing: 10) {
                    if let track = model.notebookTrack(for: work) {
                        OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else { Image(systemName: "music.note").frame(width: 36, height: 36).foregroundStyle(Palette.muted) }
                    Text((work == nil ? "" : model.t("radio.noteLinked") + " · ") + workTitle)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("notebookChooseWork").disabled(busy || stale)
            if work != nil {
                Button { work = nil; quote = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel(model.t("notebookNoWork"))
                    .accessibilityIdentifier("notebookUnlinkWork").disabled(busy || stale)
            }
        }.padding(10).frame(minHeight: 56).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
    private func save() {
        guard !busy, !stale else { return }
        guard hasText else { model.showRadioToast(model.t("radio.noteEmpty")); return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTitle = trimmedTitle.isEmpty ? (quote.map { String($0.prefix(PlatformNotebookStore.maximumTitleLength)) } ?? model.t("notebookUntitled")) : trimmedTitle
        let draft = NotebookDraft(id: draftID, work: work, title: savedTitle, body: bodyText, topicID: topicID, quote: quote)
        working = true; failed = false
        Task {
            let success = await model.saveNotebook(draft, expectedEpoch: context.epoch, expectedVersion: context.note?.version, scope: context.scope)
            working = false
            if success { dismiss(); onSaved?() } else { failed = true }
        }
    }
}

private struct NotebookPaperLines: View {
    let spacing: Double
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            var y = CGFloat(spacing)
            while y < size.height {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)); y += spacing
            }
            context.stroke(lines, with: .color(Palette.line), lineWidth: 1)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PlatformNotebookSongPicker: View {
    @Bindable var model: AppModel
    @Binding var selection: NotebookWork?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var songs: [Track] {
        var seen = Set<String>()
        let candidates = model.tracks + model.featuredTracks + model.platformFavorites.compactMap(\.track)
        return candidates.filter { track in
            guard track.release != nil, seen.insert(track.id).inserted else { return false }
            return query.isEmpty || track.title.localizedStandardContains(query) || track.artist.localizedStandardContains(query)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Button(model.t("notebookNoWork")) { selection = nil; dismiss() }.frame(minHeight: 44).accessibilityIdentifier("notebookNoWork")
                    .listRowBackground(Palette.panel)
                if songs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.t("notebookNoSongs")).font(.headline)
                        Text(model.t("notebookNoSongsDetail")).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 12).listRowBackground(Palette.panel)
                }
                ForEach(songs) { track in
                    Button {
                        guard let slug = track.release?.slug else { return }
                        selection = .init(id: track.id, slug: slug); dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).foregroundStyle(.primary)
                                Text(track.artist).font(.caption).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if selection?.id == track.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: 48)
                    }.accessibilityIdentifier("notebook.song." + track.id).listRowBackground(Palette.panel)
                }
            }.scrollContentBackground(.hidden).background { OrbitBackground() }
                .searchable(text: $query, prompt: model.t("notebookSongSearch"))
                .navigationTitle(model.t("notebookChooseWork")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("close")) { dismiss() } } }
        }.tint(Palette.accent).accessibilityIdentifier("notebookSongPicker")
    }
}

private struct PlatformNotebookTopics: View {
    @Bindable var model: AppModel
    let context: PlatformNotebookEditorContext
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TopicEditorContext?
    @State private var deleting: NotebookTopic?
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var working = false
    @State private var failed = false
    private var stale: Bool { model.scope != context.scope || model.notebookState?.epoch != context.epoch }
    private var busy: Bool { working || model.notebookBusy }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.notebookState?.topics.isEmpty != false { Text(model.t("notebookNoTopics")).foregroundStyle(Palette.muted) }
                    ForEach(model.notebookState?.topics ?? [], id: \.id) { topic in
                        HStack(alignment: .center, spacing: 12) {
                            Text(topic.name).frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                Button(model.t("notebookRenameTopic")) { editing = .init(topic: topic) }
                                Button(model.t("notebookDeleteTopic"), role: .destructive) { deleting = topic; confirmDelete = true }
                            } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel(model.t("notebookManageTopics") + ", " + topic.name)
                                .accessibilityIdentifier("notebook.topic.actions." + topic.id.uuidString).disabled(busy || stale)
                        }
                    }
                    Button { editing = .init(topic: nil) } label: { Label(model.t("notebookNewTopic"), systemImage: "plus") }
                        .frame(minHeight: 44).disabled(busy || stale).accessibilityIdentifier("notebookNewTopic")
                }.listRowBackground(Palette.panel)
                Section {
                    Button(model.t("notebookClear"), role: .destructive) { confirmClear = true }
                        .frame(minHeight: 44).disabled(busy || stale || (model.notebookState?.notes.isEmpty == true && model.notebookState?.topics.isEmpty == true))
                        .accessibilityIdentifier("notebookClear")
                } footer: { Text(model.t("notebookLocalOnly")) }.listRowBackground(Palette.panel)
                if stale { Section { Text(model.t("notebookStaleDetail")).foregroundStyle(Palette.muted) }.listRowBackground(Palette.panel) }
                else if failed { Section { NotebookFailure(model: model) }.listRowBackground(Palette.panel) }
            }.scrollContentBackground(.hidden).background { OrbitBackground() }
                .navigationTitle(model.t("notebookManageTopics")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("close")) { dismiss() }.disabled(busy) } }
                .sheet(item: $editing) { item in NotebookTopicEditor(model: model, context: context, topic: item.topic) }
                .alert(model.t("notebookDeleteTopicConfirm"), isPresented: $confirmDelete) {
                    Button(model.t("notebookDeleteTopic"), role: .destructive) {
                        guard let topic = deleting else { return }
                        working = true; failed = false
                        Task { failed = !(await model.removeNotebookTopic(id: topic.id, expectedEpoch: context.epoch, scope: context.scope)); working = false }
                    }
                    Button(model.t("cancel"), role: .cancel) {}
                } message: { Text(model.t("notebookDeleteTopicDetail")) }
                .alert(model.t("notebookClearConfirm"), isPresented: $confirmClear) {
                    Button(model.t("notebookClear"), role: .destructive) {
                        working = true; failed = false
                        Task {
                            let success = await model.clearNotebook(expectedEpoch: context.epoch, scope: context.scope)
                            working = false
                            if success { dismiss() } else { failed = true }
                        }
                    }
                    Button(model.t("cancel"), role: .cancel) {}
                } message: { Text(model.t("notebookClearDetail")) }
        }.tint(Palette.accent).interactiveDismissDisabled(busy)
            .accessibilityIdentifier("notebookTopics")
    }
    private struct TopicEditorContext: Identifiable { let id = UUID(); let topic: NotebookTopic? }
}

private struct NotebookTopicEditor: View {
    @Bindable var model: AppModel
    let context: PlatformNotebookEditorContext
    let topic: NotebookTopic?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var working = false
    @State private var failed = false
    @State private var confirmDiscard = false
    init(model: AppModel, context: PlatformNotebookEditorContext, topic: NotebookTopic?) {
        self.model = model; self.context = context; self.topic = topic; _name = State(initialValue: topic?.name ?? "")
    }
    private var dirty: Bool { name != (topic?.name ?? "") }
    private var stale: Bool { model.scope != context.scope || model.notebookState?.epoch != context.epoch }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(model.t("notebookTopicName"), text: $name).disabled(working || model.notebookBusy).accessibilityIdentifier("notebookTopicName")
                } footer: { Text(model.t("notebookTopicLimits")) }.listRowBackground(Palette.panel)
                if stale { Section { Text(model.t("notebookStaleDetail")).foregroundStyle(Palette.muted) }.listRowBackground(Palette.panel) }
                else if failed { Section { NotebookFailure(model: model) }.listRowBackground(Palette.panel) }
            }.scrollContentBackground(.hidden).background { OrbitBackground() }
                .navigationTitle(model.t(topic == nil ? "notebookNewTopic" : "notebookRenameTopic")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.t("close")) { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(working)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.t("notebookSaveTopic")) {
                            working = true; failed = false
                            Task {
                                let success = await model.saveNotebookTopic(id: topic?.id, name: name, expectedEpoch: context.epoch, scope: context.scope)
                                working = false
                                if success { dismiss() } else { failed = true }
                            }
                        }.disabled(working || model.notebookBusy || stale || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("notebookSaveTopic")
                    }
                }
                .alert(model.t("notebookDiscardConfirm"), isPresented: $confirmDiscard) {
                    Button(model.t("notebookDiscard"), role: .destructive) { dismiss() }
                    Button(model.t("notebookKeepEditing"), role: .cancel) {}
                }
        }.tint(Palette.accent).interactiveDismissDisabled(dirty || working)
    }
}

private struct NotebookFailure: View {
    let model: AppModel
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.t(model.notebookErrorKey ?? "notebookError"), systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let retry { Button(model.t("retry"), action: retry).frame(minHeight: 44).disabled(model.notebookBusy) }
        }.accessibilityIdentifier("notebookError")
    }
}
