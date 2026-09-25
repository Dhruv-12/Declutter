import Photos
import SwiftUI

/// The only place anything gets deleted. Shows exactly what will be removed and how much space
/// it frees. Tap any item to keep it.
struct ReviewView: View {
    let plan: CleanupPlan

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kept: Set<String> = []
    @State private var isDeleting = false
    @State private var confirmingContacts = false
    @State private var errorMessage: String?
    @State private var result: CleanupResult?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.gridGap), count: 4)

    private var media: [MediaItem] {
        plan.mediaSections.flatMap(\.items).filter { !kept.contains($0.id) }
    }

    private var contacts: [ContactSummary] {
        plan.contacts.filter { !kept.contains($0.id) }
    }

    private var itemCount: Int { media.count + contacts.count }

    var body: some View {
        if let result {
            SpaceFreedView(result: result) {
                model.returnHome(after: result)
                dismiss()
            }
        } else {
            review
        }
    }

    private var review: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing * 1.5) {
                    header
                    ForEach(plan.mediaSections) { section in
                        mediaSection(section)
                    }
                    if !plan.contacts.isEmpty {
                        contactSection
                    }
                    notes
                }
                .padding(.horizontal, Theme.page)
                .padding(.vertical, Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Review and delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                        .accessibilityIdentifier("review.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) { deleteBar }
            .interactiveDismissDisabled(isDeleting)
            .confirmationDialog(
                "Permanently delete \(counted(contacts.count, "contact"))?",
                isPresented: $confirmingContacts,
                titleVisibility: .visible
            ) {
                Button("Delete \(itemCount) item\(itemCount == 1 ? "" : "s")", role: .destructive) { delete() }
            } message: {
                Text("Contacts can't be recovered after they're deleted.")
            }
            .alert("Couldn't delete", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ByteFormat.string(media.totalSize))
                .font(.bigNumber)
                .foregroundStyle(Theme.pine)
                .contentTransition(.numericText())
            Text("will be freed")
                .font(.heading(.headline))
                .foregroundStyle(Theme.secondaryText)
            Text(countsText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.pine)
                .padding(.top, 6)
            Text("Everything below will be deleted. Tap anything you want to keep.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card(padding: 20)
        .tapAnimation(value: kept)
    }

    private func mediaSection(_ section: CleanupPlan.MediaSection) -> some View {
        let remaining = section.items.filter { !kept.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                category: section.category,
                detail: "\(remaining.count) of \(section.items.count) · \(ByteFormat.string(remaining.totalSize))"
            )
            if section.category == .similarPhotos && plan.fullySelectedGroups > 0 {
                Label(
                    "In \(plan.fullySelectedGroups) group\(plan.fullySelectedGroups == 1 ? "" : "s"), every photo is selected, so none of those shots would be kept.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.coralText)
            }
            LazyVGrid(columns: columns, spacing: Theme.gridGap) {
                ForEach(section.items) { item in
                    SelectableThumbnail(
                        asset: item.asset,
                        isSelected: !kept.contains(item.id),
                        badge: item.asset.mediaType == .video ? item.asset.duration.durationText : nil
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(kept.contains(item.id) ? 0.5 : 1)
                    .onTapGesture { toggleKeep(item.id) }
                    .accessibilityHint("Double-tap to keep or remove")
                }
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                category: .duplicateContacts,
                detail: "\(contacts.count) of \(plan.contacts.count)"
            )
            VStack(spacing: 12) {
                ForEach(plan.contacts) { contact in
                    ContactRow(contact: contact, isSelected: !kept.contains(contact.id))
                        .opacity(kept.contains(contact.id) ? 0.5 : 1)
                        .contentShape(.rect)
                        .onTapGesture { toggleKeep(contact.id) }
                }
            }
            .card()
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plan.mediaSections.isEmpty {
                Label("Photos and videos move to Recently Deleted in the Photos app. You can recover them there for 30 days. The space is fully freed when they leave Recently Deleted.", systemImage: "arrow.uturn.backward.circle")
            }
            if !plan.contacts.isEmpty {
                Label("Deleted contacts can't be recovered.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.coralText)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
    }

    private var deleteBar: some View {
        Button(role: .destructive) {
            if contacts.isEmpty {
                delete()
            } else {
                Haptics.warning()
                confirmingContacts = true
            }
        } label: {
            if isDeleting {
                ProgressView().tint(Theme.onCoral)
            } else {
                Text(itemCount == 0 ? "Nothing to delete" : "Delete \(itemCount) item\(itemCount == 1 ? "" : "s")" + (media.isEmpty ? "" : " · \(ByteFormat.string(media.totalSize))"))
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.destructive)
        .disabled(itemCount == 0 || isDeleting)
        .accessibilityIdentifier("review.delete")
        .padding(.horizontal, Theme.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            Theme.mist
                .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    // MARK: - Actions

    private var countsText: String {
        let photos = media.filter { $0.asset.mediaType != .video }.count
        let videos = media.count - photos
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) photo\(photos == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        if !contacts.isEmpty { parts.append("\(contacts.count) contact\(contacts.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private func toggleKeep(_ id: String) {
        Haptics.select()
        if kept.contains(id) { kept.remove(id) } else { kept.insert(id) }
    }

    private func delete() {
        Haptics.confirm()
        isDeleting = true
        Task {
            do {
                let result = try await model.performCleanup(media: media, contacts: contacts)
                self.result = result
            } catch CleanupError.cancelled {
                // The user declined the iOS prompt; stay here so they can change their mind.
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }
}

private struct SectionTitle: View {
    let category: CleanupCategory
    let detail: String

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .tintedCircle(category.tint, size: 30)
                Text(category.title)
                    .font(.heading(.headline))
                    .foregroundStyle(Theme.pine)
            }
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
