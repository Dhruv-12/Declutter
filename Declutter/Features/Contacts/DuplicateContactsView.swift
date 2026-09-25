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
            .navigationTitle("Duplicate contacts")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                if model.contactsStatus.canRead && !contacts.groups.isEmpty {
                    SelectionBar(count: contacts.selection.count, singular: "contact", plural: "contacts") {
                        reviewPlan = model.makePlan(for: [.duplicateContacts])
                    }
                }
            }
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
            if model.contactsStatus == .notDetermined {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Allow contacts access",
                    message: "Declutter looks for duplicate contacts on this iPhone. Your contacts never leave it.",
                    actionTitle: "Allow contacts access"
                ) {
                    Task { await model.requestContactsAccess() }
                }
            } else {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "Contacts access is off",
                    message: "Turn on Contacts access in Settings so Declutter can look for duplicates.",
                    actionTitle: "Open Settings"
                ) {
                    SystemSettings.open()
                }
            }
        } else {
            switch contacts.state {
            case .idle:
                LoadingView(text: "Checking contacts…")
                    .task { await contacts.scan() }
            case .scanning where contacts.groups.isEmpty:
                LoadingView(text: "Checking contacts…")
            case .failed(let message):
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't read contacts",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    Task { await contacts.scan() }
                }
            default:
                if contacts.groups.isEmpty {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: "No duplicate contacts",
                        message: "Your address book is tidy. Checked \(contacts.totalContacts) contacts."
                    )
                } else {
                    groupList
                }
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ScreenSummary(
                    text: "\(contacts.groups.count) groups · \(contacts.duplicateCount) duplicates",
                    detail: "Checked \(contacts.totalContacts) contacts. Merge to combine each group into one contact, or select contacts to delete."
                )
                if model.contactsStatus.isLimited {
                    Label("Only the contacts you shared are checked.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, Theme.page)
                }
            }
            .padding(.top, Theme.gap)

            BulkActionBar {
                BulkActionButton(
                    title: "Review and merge all",
                    count: contacts.groups.count,
                    detail: "\(contacts.duplicateCount) duplicate\(contacts.duplicateCount == 1 ? "" : "s")",
                    systemImage: "arrow.triangle.merge"
                ) {
                    // Opens a list of every merged preview; nothing changes until the user confirms there.
                    mergingAll = true
                }
            }
            .padding(.vertical, Theme.gap)

            LazyVStack(spacing: Theme.spacing) {
                ForEach(contacts.groups) { group in
                    ContactGroupCard(
                        group: group,
                        selection: contacts.selection,
                        onToggle: {
                            Haptics.select()
                            contacts.toggle($0)
                        },
                        onMerge: { merging = group }
                    )
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, Theme.spacing)
        }
        .screenBackground()
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
                        .foregroundStyle(Theme.pine)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.mist, in: .capsule)
                }
            }

            ForEach(group.contacts) { contact in
                ContactRow(contact: contact, isSelected: selection.contains(contact.id))
                    .contentShape(.rect)
                    .onTapGesture { onToggle(contact.id) }
                if contact.id != group.contacts.last?.id {
                    Theme.hairline.frame(height: 1)
                }
            }

            Button(action: onMerge) {
                Label("Merge contacts", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(BrandButtonStyle(kind: .onCard))
        }
        .card()
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                let details = contact.phones + contact.emails
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
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
        MergedAvatar(imageData: contact.thumbnail, name: contact.displayName, size: size)
    }
}
