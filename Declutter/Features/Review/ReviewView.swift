import Photos
import SwiftUI

/// The only place anything gets deleted. Shows exactly what will be removed and how much space
/// it frees. Tap any item to keep it.
struct ReviewView: View {
    let plan: CleanupPlan
    var onFinished: (CleanupResult) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kept: Set<String> = []
    @State private var isDeleting = false
    @State private var confirmingContacts = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 4)]

    private var media: [MediaItem] {
        plan.mediaSections.flatMap(\.items).filter { !kept.contains($0.id) }
    }

    private var contacts: [ContactSummary] {
        plan.contacts.filter { !kept.contains($0.id) }
    }

    private var itemCount: Int { media.count + contacts.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(plan.mediaSections) { section in
                        mediaSection(section)
                    }
                    if !plan.contacts.isEmpty {
                        contactSection
                    }
                    notes
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .safeAreaInset(edge: .bottom) { deleteBar }
            .interactiveDismissDisabled(isDeleting)
            .confirmationDialog(
                "Permanently delete \(contacts.count) contacts?",
                isPresented: $confirmingContacts,
                titleVisibility: .visible
            ) {
                Button("Delete \(itemCount) Items", role: .destructive) { delete() }
            } message: {
                Text("Contacts can't be recovered after they're deleted.")
            }
            .alert("Couldn't Delete", isPresented: Binding(
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
            Text("You'll free up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ByteFormat.string(media.totalSize))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
            Text(countsText)
                .font(.subheadline.weight(.medium))
            Text("Tap anything you want to keep.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .animation(.default, value: media.count)
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
                .font(.caption)
                .foregroundStyle(.orange)
            }
            LazyVGrid(columns: columns, spacing: 4) {
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
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plan.mediaSections.isEmpty {
                Label("Photos and videos move to Recently Deleted in the Photos app. You can recover them there for 30 days. The space is fully freed when they leave Recently Deleted.", systemImage: "arrow.uturn.backward.circle")
            }
            if !plan.contacts.isEmpty {
                Label("Deleted contacts can't be recovered.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var deleteBar: some View {
        Button(role: .destructive) {
            if contacts.isEmpty { delete() } else { confirmingContacts = true }
        } label: {
            Group {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Text(itemCount == 0 ? "Nothing Selected" : "Delete \(itemCount) Item\(itemCount == 1 ? "" : "s")")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(itemCount == 0 || isDeleting)
        .padding()
        .background(.bar)
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
        if kept.contains(id) { kept.remove(id) } else { kept.insert(id) }
    }

    private func delete() {
        isDeleting = true
        Task {
            do {
                let result = try await model.performCleanup(media: media, contacts: contacts)
                onFinished(result)
                dismiss()
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
            Label(category.title, systemImage: category.systemImage)
                .font(.headline)
                .foregroundStyle(category.tint)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
