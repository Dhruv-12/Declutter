import Contacts
import SwiftUI

struct DuplicateContactsView: View {
    @Environment(AppModel.self) private var model
    @State private var merging: ContactGroup?
    @State private var reviewPlan: CleanupPlan?
    @State private var mergingAll = false

    private var contacts: ContactsModel { model.contacts }

    var body: some View {
        content
            .navigationTitle("Duplicate Contacts")
            .safeAreaInset(edge: .bottom) {
                if !contacts.selection.isEmpty {
                    ContactSelectionBar(count: contacts.selection.count) {
                        reviewPlan = model.makePlan(for: [.duplicateContacts])
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: contacts.selection.isEmpty)
            .refreshable { await contacts.scan() }
            .sheet(item: $merging) { group in
                MergeSheet(group: group) { draft in
                    try await contacts.merge(draft)
                }
            }
            .sheet(isPresented: $mergingAll) {
                MergeAllSheet(groups: contacts.groups)
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
    }

    @ViewBuilder private var content: some View {
        if !model.contactsStatus.canRead {
            ContentUnavailableView {
                Label("Contacts Access Needed", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Allow Contacts access so Declutter can look for duplicates on this iPhone.")
            } actions: {
                if model.contactsStatus == .notDetermined {
                    Button("Allow Contacts") { Task { await model.requestContactsAccess() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Open Settings") { SystemSettings.open() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            switch contacts.state {
            case .idle:
                ProgressView("Checking contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await contacts.scan() }
            case .scanning where contacts.groups.isEmpty:
                ProgressView("Checking contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Read Contacts", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await contacts.scan() } }
                }
            default:
                if contacts.groups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates",
                        systemImage: "person.2.badge.gearshape",
                        description: Text("Checked \(contacts.totalContacts) contacts. Everything looks tidy.")
                    )
                } else {
                    groupList
                }
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(contacts.groups.count) groups · \(contacts.duplicateCount) duplicates")
                    .font(.subheadline.weight(.medium))
                Text("Checked \(contacts.totalContacts) contacts. Merge to combine details into one contact, or select contacts to delete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.contactsStatus.isLimited {
                    Label("Only the contacts you shared are checked.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            BulkActionBar {
                BulkActionButton(
                    title: "Merge all",
                    count: contacts.groups.count,
                    detail: "\(contacts.duplicateCount) duplicate\(contacts.duplicateCount == 1 ? "" : "s")",
                    systemImage: "arrow.triangle.merge"
                ) {
                    // Opens a list of every merged preview; nothing changes until the user confirms there.
                    mergingAll = true
                }
            }
            .padding(.top, 8)

            LazyVStack(spacing: 16) {
                ForEach(contacts.groups) { group in
                    ContactGroupCard(
                        group: group,
                        selection: contacts.selection,
                        onToggle: { contacts.toggle($0) },
                        onMerge: { merging = group }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ContactGroupCard: View {
    let group: ContactGroup
    let selection: Set<String>
    let onToggle: (String) -> Void
    let onMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(group.reasons, id: \.self) { reason in
                    Text(reason.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CleanupCategory.duplicateContacts.tint.opacity(0.15), in: .capsule)
                        .foregroundStyle(CleanupCategory.duplicateContacts.tint)
                }
            }

            ForEach(group.contacts) { contact in
                ContactRow(contact: contact, isSelected: selection.contains(contact.id))
                    .contentShape(.rect)
                    .onTapGesture { onToggle(contact.id) }
                if contact.id != group.contacts.last?.id { Divider() }
            }

            Button(action: onMerge) {
                Label("Merge \(group.contacts.count) Contacts", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CleanupCategory.duplicateContacts.tint)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

struct ContactRow: View {
    let contact: ContactSummary
    var isSelected: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body.weight(.medium))
                let details = contact.phones + contact.emails
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let isSelected {
                SelectionCheckmark(isSelected: isSelected)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}

struct ContactAvatar: View {
    let contact: ContactSummary
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = contact.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

private struct ContactSelectionBar: View {
    let count: Int
    let onReview: () -> Void

    var body: some View {
        HStack {
            Text("\(count) selected")
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()
            Button("Review", action: onReview)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
