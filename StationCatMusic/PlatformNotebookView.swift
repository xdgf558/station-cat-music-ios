import SwiftUI

/// Presentation snapshots retain the epoch and scope that the user actually opened.
/// An editor can never silently save into a new notebook after clearing or switching accounts.
struct PlatformNotebookEditorContext: Identifiable {
    let id = UUID()
    let note: NotebookNote?
    let work: NotebookWork?
    let epoch: UUID
    let scope: AccountScope

    init(note: NotebookNote? = nil, work: NotebookWork? = nil, state: NotebookState, scope: AccountScope) {
        self.note = note; self.work = note?.work ?? work
        self.epoch = state.epoch; self.scope = scope
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
            let category: Bool
            switch filter {
            case .all: category = true
            case .uncategorized: category = note.topicID == nil
            case .topic(let id): category = note.topicID == id
            }
            guard category else { return false }
            guard !text.isEmpty else { return true }
            let workTitle = model.notebookTrack(for: note.work)?.title ?? model.notebookBookmark(for: note.work)?.title ?? ""
            let topic = model.notebookState?.topics.first(where: { $0.id == note.topicID })?.name ?? ""
            return [note.title, note.body, topic, workTitle].contains { $0.localizedStandardContains(text) }
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Keep the page marker on one semantic element. An identifier
                // on the inset's outer container can overwrite its button IDs.
                Text(model.t("notebookTitle")).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("notebookPage")
                search
                filters
                if let state = model.notebookState {
                    if notes.isEmpty {
                        empty(state.notes.isEmpty)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(notes, id: \.id) { note in
                                Button {
                                    editor = .init(note: note, state: state, scope: model.scope)
                                } label: { PlatformNotebookRow(model: model, note: note) }
                                    .buttonStyle(.plain).accessibilityIdentifier("notebook.note." + note.id.uuidString)
                                Divider().overlay(Palette.line)
                            }
                        }
                    }
                } else if model.notebookErrorKey == nil {
                    ProgressView(model.t("notebookLoading")).frame(maxWidth: .infinity, minHeight: 160)
                }
                if model.notebookErrorKey != nil { NotebookFailure(model: model, retry: { Task { await model.refreshNotebook() } }) }
                Text(model.t("notebookLocalOnly")).font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
                .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }.background { OrbitBackground().accessibilityHidden(true) }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { notebookActions }
            .toolbar(.visible, for: .navigationBar)
            .task { await model.refreshNotebook() }
            .sheet(item: $editor, onDismiss: openPendingWork) { context in
                PlatformNotebookEditor(model: model, context: context) { pendingWork = $0 }
            }
            .sheet(item: $topics) { context in PlatformNotebookTopics(model: model, context: context) }
            .onChange(of: model.notebookState?.topics.map(\.id)) { _, ids in
                if case .topic(let id) = filter, !(ids ?? []).contains(id) { filter = .all }
            }
    }

    /// Reserve space above the system tab bar; the list can scroll without
    /// placing its primary actions beneath the floating tab presentation.
    private var notebookActions: some View {
        VStack(spacing: 4) {
            Button {
                guard let state = model.notebookState else { return }
                editor = .init(state: state, scope: model.scope)
            } label: {
                Label(model.t("notebookNew"), systemImage: "square.and.pencil")
                    .font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Palette.background).background(Palette.accent, in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(.plain).accessibilityIdentifier("notebookNew")
                .disabled(model.notebookState == nil || model.notebookBusy)
            Button {
                guard let state = model.notebookState else { return }
                topics = .init(state: state, scope: model.scope)
            } label: {
                HStack(spacing: 10) {
                    Text(model.t("notebookManageTopics")).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                }.font(.subheadline).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.notebookState == nil || model.notebookBusy)
                .accessibilityIdentifier("notebookManageTopics")
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(Palette.background)
    }

    private var search: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Palette.muted).accessibilityHidden(true)
            TextField(model.t("notebookSearch"), text: $query).textInputAutocapitalization(.never)
                .autocorrectionDisabled().accessibilityIdentifier("notebookSearch")
        }.padding(.horizontal, 17).frame(minHeight: 54)
            .background(Palette.panel.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(Palette.accent.opacity(0.24), lineWidth: 1))
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(model.t("notebookAll"), filter: .all, id: "all")
                ForEach(model.notebookState?.topics ?? [], id: \.id) { topic in
                    chip(topic.name, filter: .topic(topic.id), id: topic.id.uuidString)
                }
                chip(model.t("notebookUncategorized"), filter: .uncategorized, id: "uncategorized")
            }.padding(.vertical, 2)
        }
    }
    private func chip(_ title: String, filter value: Filter, id: String) -> some View {
        Button { filter = value } label: {
            Text(title).font(.subheadline.weight(.medium)).fixedSize().padding(.horizontal, 20).frame(minHeight: 44)
                .foregroundStyle(filter == value ? Palette.background : Palette.muted)
                .background(filter == value ? Palette.accent : Palette.panel, in: Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: filter == value ? 0 : 1))
        }.buttonStyle(.plain).accessibilityIdentifier("notebook.filter." + id)
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
    private func empty(_ noNotes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: noNotes ? "text.book.closed" : "magnifyingglass").font(.largeTitle).foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text(model.t(noNotes ? "notebookEmpty" : "notebookNoResults")).font(.title3.weight(.semibold))
            Text(model.t(noNotes ? "notebookEmptyDetail" : "notebookNoResultsDetail")).foregroundStyle(Palette.muted)
        }.padding(.vertical, 28).frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .accessibilityIdentifier("notebookEmpty")
    }
    private func openPendingWork() {
        guard let work = pendingWork else { return }
        pendingWork = nil; model.openNotebookWork(work)
    }
}

private struct PlatformNotebookRow: View {
    let model: AppModel
    let note: NotebookNote
    @Environment(\.dynamicTypeSize) private var typeSize
    private var track: Track? { model.notebookTrack(for: note.work) }
    private var title: String {
        note.title.isEmpty ? (track?.title ?? model.notebookBookmark(for: note.work)?.title ?? model.t("notebookUntitled")) : note.title
    }
    private var topic: String { model.notebookState?.topics.first(where: { $0.id == note.topicID })?.name ?? model.t("notebookUncategorized") }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if !typeSize.isAccessibilitySize {
                if let track {
                    OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                } else {
                    Image(systemName: "text.book.closed").font(.title2).foregroundStyle(Palette.accent)
                        .frame(width: 76, height: 76).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15)).accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !note.body.isEmpty { Text(note.body).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(typeSize.isAccessibilitySize ? 3 : 2) }
                Text(topic + " · " + note.updatedAt.formatted(.dateTime.month().day().locale(Locale(identifier: model.locale))))
                    .font(.caption).foregroundStyle(Palette.accent).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted).padding(.top, 9).accessibilityHidden(true)
        }.padding(.vertical, 20).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct PlatformNotebookEditor: View {
    @Bindable var model: AppModel
    let context: PlatformNotebookEditorContext
    var openWork: (NotebookWork) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var bodyText: String
    @State private var topicID: UUID?
    @State private var work: NotebookWork?
    @State private var showSongs = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var working = false
    @State private var failed = false
    @State private var draftID: UUID

    init(model: AppModel, context: PlatformNotebookEditorContext, openWork: @escaping (NotebookWork) -> Void) {
        self.model = model; self.context = context; self.openWork = openWork
        _title = State(initialValue: context.note?.title ?? ""); _bodyText = State(initialValue: context.note?.body ?? "")
        _topicID = State(initialValue: context.note?.topicID); _work = State(initialValue: context.work)
        _draftID = State(initialValue: context.note?.id ?? UUID())
    }
    private var dirty: Bool { title != (context.note?.title ?? "") || bodyText != (context.note?.body ?? "") || topicID != context.note?.topicID || work != context.work }
    private var stale: Bool { model.scope != context.scope || model.notebookState?.epoch != context.epoch }
    private var busy: Bool { working || model.notebookBusy }
    private var hasText: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var workTitle: String { model.notebookTrack(for: work)?.title ?? model.notebookBookmark(for: work)?.title ?? model.t(work == nil ? "notebookNoWork" : "notebookWorkUnavailable") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(model.t("notebookNoteTitle"), text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold)).disabled(busy).accessibilityIdentifier("notebookTitleField")
                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty { Text(model.t("notebookBodyPlaceholder")).foregroundStyle(Palette.muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                        TextEditor(text: $bodyText).frame(minHeight: 210).scrollContentBackground(.hidden)
                            .disabled(busy).accessibilityLabel(model.t("notebookBody")).accessibilityIdentifier("notebookBodyField")
                    }
                } footer: { Text(model.t("notebookTextLimits")) }.listRowBackground(Palette.panel)
                Section(model.t("notebookWork")) {
                    Button { showSongs = true } label: {
                        HStack(spacing: 12) {
                            if let track = model.notebookTrack(for: work) {
                                OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            Text(workTitle).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("notebookChooseWork").disabled(busy || stale)
                    if let work {
                        Button(model.t("notebookOpenWork")) { openWork(work); dismiss() }
                            .disabled(dirty || busy || stale).accessibilityIdentifier("notebookOpenWork")
                    }
                }.listRowBackground(Palette.panel)
                Section {
                    Picker(model.t("notebookTopic"), selection: $topicID) {
                        Text(model.t("notebookUncategorized")).tag(Optional<UUID>.none)
                        ForEach(model.notebookState?.topics ?? [], id: \.id) { topic in Text(topic.name).tag(Optional(topic.id)) }
                    }.accessibilityIdentifier("notebookTopicPicker").disabled(busy || stale)
                } footer: { Text(model.t("notebookLocalOnly")) }.listRowBackground(Palette.panel)
                if stale {
                    Section { Label(model.t("notebookStaleDetail"), systemImage: "exclamationmark.circle").foregroundStyle(Palette.muted) }.listRowBackground(Palette.panel)
                } else if failed {
                    Section { NotebookFailure(model: model) }.listRowBackground(Palette.panel)
                }
                if context.note != nil {
                    Section { Button(model.t("notebookDelete"), role: .destructive) { confirmDelete = true }.disabled(busy || stale).accessibilityIdentifier("notebookDelete") }.listRowBackground(Palette.panel)
                }
            }.scrollContentBackground(.hidden).background { OrbitBackground() }
                .navigationTitle(model.t(context.note == nil ? "notebookNew" : "notebookEdit")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.t("close")) { if dirty { confirmDiscard = true } else { dismiss() } }
                            .disabled(busy).accessibilityIdentifier("notebookEditorClose")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            working = true; failed = false
                            Task {
                                let success = await model.saveNotebook(.init(id: draftID, work: work, title: title, body: bodyText, topicID: topicID), expectedEpoch: context.epoch, expectedVersion: context.note?.version, scope: context.scope)
                                working = false
                                if success { dismiss() } else { failed = true }
                            }
                        } label: {
                            if working { ProgressView().accessibilityLabel(model.t("notebookSave")) } else { Text(model.t("notebookSave")) }
                        }.disabled(busy || stale || !hasText).accessibilityIdentifier("notebookSave")
                    }
                }
                .sheet(isPresented: $showSongs) { PlatformNotebookSongPicker(model: model, selection: $work) }
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
        }.preferredColorScheme(.dark).tint(Palette.accent).interactiveDismissDisabled(dirty || busy)
            .accessibilityIdentifier("notebookEditor")
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
        }.preferredColorScheme(.dark).tint(Palette.accent).accessibilityIdentifier("notebookSongPicker")
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
        }.preferredColorScheme(.dark).tint(Palette.accent).interactiveDismissDisabled(busy)
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
        }.preferredColorScheme(.dark).tint(Palette.accent).interactiveDismissDisabled(dirty || working)
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
