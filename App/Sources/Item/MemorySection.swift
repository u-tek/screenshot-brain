import Core
import DesignSystem
import Media
import PhotosUI
import Store
import SwiftUI

/// On something done: a photo of it actually happening and a line about how it was, for the
/// did-it log. The screenshot was the plan; this is what happened.
struct MemorySection: View {
    @EnvironmentObject private var model: AppModel
    let entry: DoneEntry
    let kind: SBKind
    var onChange: (DoneEntry) -> Void = { _ in }
    @State private var draft = ""
    @State private var showsPicker = false
    @State private var picked: PhotosPickerItem?
    @State private var isAddingPhoto = false
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SBSpace.gap) {
            SBLabel("Remember it")
                .padding(.bottom, 4)
            if let photo = entry.photoName {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        AssetImage(MemoryPhotos.identifier(for: photo), maxPixelSize: 1600)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            Button { showsPicker = true } label: { Label("Change photo", systemImage: "photo") }
                            Button(role: .destructive) { removePhoto() } label: { Label("Remove photo", systemImage: "trash") }
                        } label: {
                            SBCircleLabel(.more, size: 40, onGlass: true)
                        }
                        .accessibilityLabel(Text("Photo options"))
                        .padding(12)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Your photo"))
            }
            TextField("How was it?", text: $draft, axis: .vertical)
                .font(SBFont.body(16))
                .foregroundStyle(SBColor.ink)
                .lineLimit(1...6)
                .focused($isEditing)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous).fill(SBColor.surface))
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isEditing = false }
                    }
                }
            if entry.photoName == nil {
                Button { showsPicker = true } label: {
                    SBScenarioLabel(isAddingPhoto ? "Adding it…" : "Add a photo of it", icon: .system("photo"), color: kind.core)
                }
                .buttonStyle(SBPressStyle())
                .disabled(isAddingPhoto)
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $picked, matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { item in
            guard let item else { return }
            picked = nil
            Task { await addPhoto(item) }
        }
        .onChange(of: isEditing) { editing in
            if !editing { saveNote() }
        }
        .onAppear { draft = entry.note ?? "" }
        .onDisappear { saveNote() }
    }

    private func saveNote() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (entry.note ?? ""), let database = model.services?.database else { return }
        try? database.setNote(trimmed, forEntry: entry.id)
        if entry.note == nil, !trimmed.isEmpty {
            model.analytics.track(.didItNoteAdded)
        }
        var updated = entry
        updated.note = trimmed.isEmpty ? nil : trimmed
        onChange(updated)
    }

    /// Copies the photo into the app (sized down, off the main thread) and adds it.
    private func addPhoto(_ item: PhotosPickerItem) async {
        isAddingPhoto = true
        defer { isAddingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let name = try? await Task.detached(priority: .userInitiated, operation: { try MemoryPhotos.save(data) }).value,
              let database = model.services?.database
        else { return }
        if let replaced = try? database.setPhoto(name, forEntry: entry.id) {
            MemoryPhotos.remove(replaced)
        }
        model.analytics.track(.didItPhotoAdded)
        Haptics.success()
        var updated = entry
        updated.photoName = name
        onChange(updated)
    }

    private func removePhoto() {
        guard let database = model.services?.database else { return }
        if let removed = try? database.setPhoto(nil, forEntry: entry.id) {
            MemoryPhotos.remove(removed)
        }
        var updated = entry
        updated.photoName = nil
        onChange(updated)
    }
}
