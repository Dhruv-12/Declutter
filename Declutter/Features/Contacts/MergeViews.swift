import SwiftUI

/// Edit one merge: pick the name, tick numbers and emails, choose the photo.
struct MergeEditorView: View {
    @Binding var draft: MergeDraft

    var body: some View {
        List {
            Group {
                editorSections
            }
            .listRowBackground(Theme.stone)
        }
        .brandList()
    }

    @ViewBuilder private var editorSections: some View {
            Section("Merged contact") {
                MergePreviewCard(draft: draft)
            }

            Section {
                MergeWarning(deletedCount: draft.group.contacts.count - 1)
            }

            Section("Name") {
                ForEach(draft.nameOptions) { contact in
                    ChoiceRow(
                        title: contact.displayName,
                        isChosen: !draft.useCustomName && draft.nameFromID == contact.id
                    ) {
                        draft.useCustomName = false
                        draft.nameFromID = contact.id
                    }
                }
                ChoiceRow(title: "Type a new name", isChosen: draft.useCustomName) {
                    guard !draft.useCustomName else { return }
                    // Start from the current name so small fixes are quick.
                    let words = draft.finalName.split(separator: " ").map(String.init)
                    draft.customGiven = words.first ?? ""
                    draft.customFamily = words.dropFirst().joined(separator: " ")
                    draft.useCustomName = true
                }
                if draft.useCustomName {
                    TextField("First name", text: $draft.customGiven)
                        .textContentType(.givenName)
                    TextField("Last name", text: $draft.customFamily)
                        .textContentType(.familyName)
                    if !draft.isValid {
                        Text("Enter a name.")
                            .font(.caption)
                            .foregroundStyle(Theme.coralText)
                    }
                }
            }

            if !draft.phones.isEmpty {
                Section {
                    ForEach($draft.phones) { $value in
                        ValueToggle(value: $value, systemImage: "phone")
                    }
                } header: {
                    Text("Phone numbers")
                } footer: {
                    Text("Numbers are compared by their digits, so +91 98765 43210 and 9876543210 count as the same number.")
                }
            }

            if !draft.emails.isEmpty {
                Section {
                    ForEach($draft.emails) { $value in
                        ValueToggle(value: $value, systemImage: "envelope")
                    }
                } header: {
                    Text("Emails")
                } footer: {
                    Text("Emails that differ only in capital letters count as the same.")
                }
            }

            Section("Photo") {
                PhotoChooser(draft: $draft)
            }

            Section {
                ForEach(draft.orderedContacts) { contact in
                    HStack {
                        ContactRow(contact: contact)
                        let isKept = contact.id == draft.primary.id
                        Text(isKept ? "Kept" : "Deleted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isKept ? Theme.pine : Theme.coralText)
                    }
                }
            } header: {
                Text("Contacts in this merge")
            } footer: {
                Text("Addresses, birthdays, dates, relations and social profiles from every contact are combined too.")
            }
    }
}

/// What the merged contact will look like.
struct MergePreviewCard: View {
    let draft: MergeDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                MergedAvatar(imageData: draft.photoContact?.thumbnail, name: draft.finalName, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.finalName.isEmpty ? "No name" : draft.finalName)
                        .font(.heading(.title3))
                        .foregroundStyle(Theme.pine)
                    Text("\(draft.group.contacts.count) contacts become 1")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            ForEach(draft.includedPhones) { Label($0.display, systemImage: "phone") }
            ForEach(draft.includedEmails) { Label($0.display, systemImage: "envelope") }
            if draft.includedPhones.isEmpty && draft.includedEmails.isEmpty {
                Text("No phone numbers or emails")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.pine)
        .padding(.vertical, 4)
        .tapAnimation(value: draft)
    }
}

struct MergeWarning: View {
    let deletedCount: Int

    var body: some View {
        Label {
            Text("Merging can't be undone. The other \(deletedCount) contact\(deletedCount == 1 ? " is" : "s are") permanently deleted after their details are copied. Notes can't be read by apps, so notes on them won't be copied.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.coralText)
    }
}

private struct ChoiceRow: View {
    let title: String
    let isChosen: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.pine)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark").foregroundStyle(Theme.pine).bold()
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

private struct ValueToggle: View {
    @Binding var value: DraftValue
    let systemImage: String

    var body: some View {
        Toggle(isOn: $value.isIncluded) {
            VStack(alignment: .leading, spacing: 2) {
                Label(value.display, systemImage: systemImage)
                    .foregroundStyle(Theme.pine)
                if value.duplicatesRemoved > 0 {
                    Text("\(value.duplicatesRemoved) duplicate\(value.duplicatesRemoved == 1 ? "" : "s") removed")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.leading, 30)
                }
            }
        }
        .onChange(of: value.isIncluded) { Haptics.select() }
    }
}

private struct PhotoChooser: View {
    @Binding var draft: MergeDraft

    var body: some View {
        if draft.photoOptions.isEmpty {
            Text("None of these contacts has a photo.")
                .foregroundStyle(Theme.secondaryText)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(draft.photoOptions) { contact in
                        option(isChosen: draft.photoFrom == contact.id, label: contact.displayName) {
                            ContactAvatar(contact: contact, size: 56)
                        } action: {
                            draft.photoFrom = contact.id
                        }
                    }
                    option(isChosen: draft.photoFrom == nil, label: "No photo") {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 56, height: 56)
                            .background(Theme.mist, in: .circle)
                    } action: {
                        draft.photoFrom = nil
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func option(
        isChosen: Bool,
        label: String,
        @ViewBuilder image: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(spacing: 6) {
                image()
                    .overlay {
                        Circle().strokeBorder(isChosen ? Theme.pine : .clear, lineWidth: 3)
                    }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 70)
                    .foregroundStyle(isChosen ? Theme.pine : Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

struct MergedAvatar: View {
    let imageData: Data?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                let initials = String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.pine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.mist)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

// MARK: - Sheets

/// Merge one group: edit it, then confirm.
struct MergeSheet: View {
    let perform: (MergeDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MergeDraft
    @State private var confirming = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(group: ContactGroup, perform: @escaping (MergeDraft) async throws -> Void) {
        self.perform = perform
        _draft = State(initialValue: MergeDraft(group: group))
    }

    var body: some View {
        NavigationStack {
            MergeEditorView(draft: $draft)
                .navigationTitle("Merge contacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isWorking)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        Haptics.warning()
                        confirming = true
                    } label: {
                        if isWorking {
                            ProgressView().tint(Theme.onCoral)
                        } else {
                            Text("Merge contacts")
                        }
                    }
                    .buttonStyle(.destructive)
                    .disabled(!draft.isValid || isWorking)
                    .padding(.horizontal, Theme.page)
                    .padding(.vertical, 12)
                    .background(Theme.mist.ignoresSafeArea())
                }
                .confirmationDialog(
                    "Merge \(draft.group.contacts.count) contacts into one?",
                    isPresented: $confirming,
                    titleVisibility: .visible
                ) {
                    Button("Merge contacts", role: .destructive) { merge() }
                } message: {
                    Text("This can't be undone.")
                }
                .alert("Couldn't merge", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func merge() {
        Haptics.confirm()
        isWorking = true
        Task {
            do {
                try await perform(draft)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Merge every duplicate group: see each merged preview, edit any, skip any, then confirm once.
struct MergeAllSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [MergeDraft]
    @State private var confirming = false
    @State private var mergedSoFar: Int?
    @State private var failures: [String] = []
    @State private var showingFailures = false

    init(groups: [ContactGroup]) {
        _drafts = State(initialValue: groups.map(MergeDraft.init))
    }

    private var included: [MergeDraft] { drafts.filter(\.isIncluded) }
    private var contactsDeleted: Int { included.reduce(0) { $0 + $1.group.contacts.count - 1 } }
    private var hasInvalid: Bool { included.contains { !$0.isValid } }
    private var isWorking: Bool { mergedSoFar != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MergeWarning(deletedCount: contactsDeleted)
                    Text("Tap a group to change its name, numbers, emails or photo. Untick a group to skip it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.stone)

                Section {
                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            Button {
                                Haptics.select()
                                draft.isIncluded.toggle()
                            } label: {
                                SelectionCheckmark(isSelected: draft.isIncluded)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(draft.isIncluded ? "Skip this group" : "Include this group")

                            NavigationLink(value: draft.id) {
                                MergeDraftRow(draft: draft)
                            }
                        }
                        .opacity(draft.isIncluded ? 1 : 0.5)
                        .listRowBackground(Theme.stone)
                    }
                } header: {
                    HStack {
                        Text("\(included.count) of \(drafts.count) groups")
                        Spacer()
                        let allIncluded = included.count == drafts.count
                        Button(allIncluded ? "Skip all" : "Include all") {
                            Haptics.select()
                            for index in drafts.indices { drafts[index].isIncluded = !allIncluded }
                        }
                        .foregroundStyle(Theme.pine)
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let index = drafts.firstIndex(where: { $0.id == id }) {
                    MergeEditorView(draft: $drafts[index])
                        .navigationTitle("Edit merge")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .brandList()
            .navigationTitle("Merge all groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .confirmationDialog(
                "Merge \(included.count) group\(included.count == 1 ? "" : "s")?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Merge \(included.count) group\(included.count == 1 ? "" : "s")", role: .destructive) { mergeAll() }
            } message: {
                Text("\(contactsDeleted) contact\(contactsDeleted == 1 ? "" : "s") will be permanently deleted after their details are copied. This can't be undone.")
            }
            .alert("Some groups weren't merged", isPresented: $showingFailures) {
                Button("OK") { dismiss() }
            } message: {
                Text(failures.joined(separator: "\n"))
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let mergedSoFar {
                ProgressView(value: Double(mergedSoFar), total: Double(max(included.count, 1)))
                    .tint(Theme.pine)
                Text("Merging \(min(mergedSoFar + 1, included.count)) of \(included.count)…")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else if hasInvalid {
                Text("Give every ticked group a name before merging.")
                    .font(.caption)
                    .foregroundStyle(Theme.coralText)
            }
            Button {
                Haptics.warning()
                confirming = true
            } label: {
                Text(included.isEmpty ? "Tick a group to merge" : "Merge \(included.count) group\(included.count == 1 ? "" : "s")")
            }
            .buttonStyle(.destructive)
            .disabled(included.isEmpty || hasInvalid || isWorking)
        }
        .padding(.horizontal, Theme.page)
        .padding(.vertical, 12)
        .background(Theme.mist.ignoresSafeArea())
    }

    private func mergeAll() {
        Haptics.confirm()
        let toMerge = included
        mergedSoFar = 0
        Task {
            failures = await model.contacts.mergeAll(toMerge) { mergedSoFar = $0 }
            mergedSoFar = nil
            if failures.isEmpty {
                Haptics.success()
                dismiss()
            } else {
                Haptics.warning()
                showingFailures = true
            }
        }
    }
}

private struct MergeDraftRow: View {
    let draft: MergeDraft

    var body: some View {
        HStack(spacing: 12) {
            MergedAvatar(imageData: draft.photoContact?.thumbnail, name: draft.finalName)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.finalName.isEmpty ? "No name" : draft.finalName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var summary: String {
        let phones = draft.includedPhones.count
        let emails = draft.includedEmails.count
        return "\(draft.group.contacts.count) → 1 · \(phones) number\(phones == 1 ? "" : "s") · \(emails) email\(emails == 1 ? "" : "s")"
    }
}
