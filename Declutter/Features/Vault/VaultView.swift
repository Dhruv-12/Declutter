import Photos
import PhotosUI
import SwiftUI

/// The private vault: set up a PIN, unlock with Face ID or the PIN, then browse, add, save back
/// to Photos, or delete. Hidden behind a cover whenever the app isn't in front.
struct VaultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private var vault: VaultModel { model.vault }

    var body: some View {
        Group {
            switch vault.state {
            case .needsSetup: VaultSetupView()
            case .locked: VaultLockedView()
            case .unlocked: VaultContentView()
            }
        }
        .navigationTitle("Private vault")
        // Inline while the PIN pad shows, so the whole pad fits on an iPhone SE.
        .navigationBarTitleDisplayMode(vault.state == .unlocked ? .large : .inline)
        .overlay {
            // Keeps vault photos out of the app switcher's snapshot.
            if scenePhase != .active && vault.state == .unlocked {
                PrivacyCover()
            }
        }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(Theme.pine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.mist)
            .ignoresSafeArea()
    }
}

// MARK: - Setup

private struct VaultSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var firstPIN: String?
    @State private var entry = ""
    @State private var mismatch = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28, weight: .semibold))
                    .tintedCircle(Tool.vault.tint, size: 64)
                VStack(spacing: Theme.gap) {
                    Text(firstPIN == nil ? "Create a PIN" : "Enter it again")
                        .font(.heading(.title3))
                        .foregroundStyle(Theme.pine)
                    // With very large text the explanation fills the screen, so it goes below the keypad.
                    if !typeSize.isAccessibilitySize { explanation }
                    if mismatch {
                        Text("Those PINs didn't match. Start again.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.coralText)
                            .multilineTextAlignment(.center)
                    }
                }
                PINPad(entry: $entry, actionTitle: firstPIN == nil ? "Next" : "Create PIN") { next() }
                if typeSize.isAccessibilitySize { explanation }
            }
            .padding(Theme.page)
        }
        .screenBackground()
    }

    private var explanation: some View {
        Text(firstPIN == nil
             ? "Photos you move here are encrypted on this iPhone and hidden from Photos. \(model.vault.biometryName ?? "Face ID") opens the vault; this 4 to 6 digit PIN is the backup."
             : "Type the same PIN to confirm it.")
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
    }

    private func next() {
        guard VaultPIN.isValid(entry) else { return }
        if let firstPIN {
            if entry == firstPIN {
                model.vault.setPIN(entry)
            } else {
                Haptics.warning()
                mismatch = true
                self.firstPIN = nil
            }
        } else {
            mismatch = false
            firstPIN = entry
        }
        entry = ""
    }
}

// MARK: - Locked

private struct VaultLockedView: View {
    @Environment(AppModel.self) private var model
    @State private var usePIN = false
    @State private var entry = ""
    @State private var wrongPIN = false

    private var vault: VaultModel { model.vault }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .tintedCircle(Tool.vault.tint, size: 64)
                Text("Your vault is locked")
                    .font(.heading(.title3))
                    .foregroundStyle(Theme.pine)

                if let biometry = vault.biometryName, !usePIN {
                    Button("Unlock with \(biometry)") { Task { await tryBiometrics() } }
                        .buttonStyle(.primary)
                    Button("Use PIN") { usePIN = true }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("vault.usePIN")
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let wait = vault.attempts.secondsLeft(at: context.date)
                        VStack(spacing: Theme.gap) {
                            if wait > 0 {
                                Text("Too many tries. Try again in \(wait) s.")
                                    .foregroundStyle(Theme.coralText)
                            } else if wrongPIN {
                                Text("That PIN isn't right.")
                                    .foregroundStyle(Theme.coralText)
                                    .accessibilityIdentifier("vault.wrongPIN")
                            }
                            PINPad(entry: $entry, actionTitle: "Unlock") { submit() }
                                .disabled(wait > 0)
                                .opacity(wait > 0 ? 0.4 : 1)
                        }
                    }
                }
            }
            .padding(Theme.page)
        }
        .screenBackground()
        .task {
            if vault.biometryName != nil && !usePIN { await tryBiometrics() }
        }
    }

    private func tryBiometrics() async {
        if !(await vault.unlockWithBiometrics()) { usePIN = true }
    }

    private func submit() {
        wrongPIN = !vault.unlock(pin: entry)
        entry = ""
    }
}

// MARK: - Unlocked

private struct VaultContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<UUID> = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isWorking = false
    @State private var progress: VaultImportProgress?
    @State private var message: String?
    @State private var failures: [VaultImportFailure] = []
    @State private var movedOriginals: [MediaItem] = []
    @State private var reviewPlan: CleanupPlan?
    @State private var confirmingDelete = false
    @State private var viewing: VaultItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.gridGap), count: 3)
    private var vault: VaultModel { model.vault }

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lock", systemImage: "lock") { vault.lock() }
                        .accessibilityIdentifier("vault.lock")
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await add(items) }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .sheet(item: $viewing) { item in VaultPhotoViewer(item: item) }
            .sheet(isPresented: Binding(get: { !failures.isEmpty }, set: { if !$0 { failures = [] } })) {
                ImportFailuresSheet(failures: failures, addedCount: movedOriginals.count)
            }
            .confirmationDialog(
                "Delete \(counted(selection.count, "photo")) from the vault?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete from vault", role: .destructive) { deleteSelected() }
            } message: {
                Text("They can't be recovered unless you've saved them to Photos first.")
            }
            .alert("Private vault", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: {
                Text(message ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if vault.items.isEmpty && !isWorking {
            EmptyStateView(
                systemImage: "lock.shield",
                title: "Your vault is empty",
                message: "Add photos to keep them encrypted on this iPhone, away from your Photos library. Nothing is uploaded."
            )
        } else {
            ScrollView {
                ScreenSummary(
                    text: "\(counted(vault.items.count, "photo")) · encrypted on this iPhone",
                    detail: "Tap to select. Touch and hold to look closer. The vault locks when you leave the app."
                )
                .padding(.top, Theme.gap)

                if isWorking {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress?.text ?? "Getting photos ready…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.pine)
                            .accessibilityIdentifier("vault.progress")
                        ProgressView(value: overallProgress)
                            .tint(Theme.pine)
                    }
                    .padding(.horizontal, Theme.page)
                    .padding(.top, Theme.gap)
                }

                LazyVGrid(columns: columns, spacing: Theme.gridGap) {
                    ForEach(vault.items) { item in
                        VaultThumbnail(item: item, isSelected: selection.contains(item.id))
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture {
                                Haptics.select()
                                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                            }
                            .onLongPressGesture { viewing = item }
                    }
                }
                .padding(.horizontal, Theme.page)
                .padding(.vertical, Theme.spacing)
            }
            .screenBackground()
        }
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: Theme.gap) {
            if !movedOriginals.isEmpty {
                Button("Review and delete \(counted(movedOriginals.count, "original"))") {
                    reviewPlan = model.makeVaultPlan(originals: movedOriginals)
                    movedOriginals = []
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("vault.reviewOriginals")
            } else if selection.isEmpty {
                PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                    Label("Add photos", systemImage: "plus")
                }
                .buttonStyle(.primary)
                .disabled(isWorking || !model.photoStatus.canRead)
                .accessibilityIdentifier("vault.add")
            } else {
                HStack(spacing: Theme.gap) {
                    Button("Save to Photos") { Task { await saveSelected() } }
                        .buttonStyle(.secondary)
                    Button("Delete") {
                        Haptics.warning()
                        confirmingDelete = true
                    }
                    .buttonStyle(.destructive)
                }
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, Theme.page)
        .padding(.vertical, 12)
        .background(Theme.mist.ignoresSafeArea())
    }

    /// Whole import, 0...1: finished photos plus the current photo's download.
    private var overallProgress: Double {
        guard let progress, progress.total > 0 else { return 0 }
        return (Double(progress.current - 1) + (progress.download ?? 0.5)) / Double(progress.total)
    }

    private func add(_ picked: [PhotosPickerItem]) async {
        let ids = picked.compactMap(\.itemIdentifier)
        pickerItems = []
        let assets = PhotoLibrary.array(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        guard !assets.isEmpty else {
            message = "Those photos couldn't be read. With limited Photos access, only photos you've shared with Declutter can be added."
            return
        }
        isWorking = true
        progress = nil
        let result = await vault.add(assets) { progress = $0 }
        isWorking = false
        progress = nil
        // Only originals that are safely in the vault can be offered for deletion.
        movedOriginals = PhotoLibrary.sized(result.copied)
        failures = result.failures
        if !result.copied.isEmpty { Haptics.success() }
        if !result.failures.isEmpty { Haptics.warning() }
    }

    private func saveSelected() async {
        isWorking = true
        do {
            try await vault.saveToPhotos(selection)
            message = "Saved \(counted(selection.count, "photo")) to Photos. They're still in the vault too."
            selection = []
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
        isWorking = false
    }

    private func deleteSelected() {
        do {
            try vault.delete(selection)
            selection = []
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct VaultThumbnail: View {
    let item: VaultItem
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.hairline
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipped()
        }
        .overlay { if isSelected { Color.black.opacity(0.22) } }
        .overlay(alignment: .bottomTrailing) { SelectionCheckmark(isSelected: isSelected).padding(6) }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.thumbRadius).strokeBorder(Theme.pine, lineWidth: 2.5)
            }
        }
        .clipShape(.rect(cornerRadius: Theme.thumbRadius))
        .contentShape(.rect)
        .task(id: item.id) { image = await model.vault.thumbnail(for: item) }
        .accessibilityElement()
        .accessibilityLabel(item.takenAt.map { "Photo from \($0.formatted(date: .long, time: .omitted))" } ?? "Photo")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("vault.thumbnail")
    }
}

private struct VaultPhotoViewer: View {
    let item: VaultItem
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { image = await model.vault.fullPhoto(for: item) }
    }
}

// MARK: - PIN pad

/// Digits entered as dots, with a number pad and one action button.
struct PINPad: View {
    @Binding var entry: String
    let actionTitle: String
    let action: () -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "delete"]

    var body: some View {
        VStack(spacing: Theme.spacing) {
            HStack(spacing: 14) {
                ForEach(0..<VaultPIN.validLengths.upperBound, id: \.self) { index in
                    Circle()
                        .fill(index < entry.count ? Theme.pineFill : Color.clear)
                        .overlay { Circle().strokeBorder(Theme.pine.opacity(index < 4 ? 0.6 : 0.25), lineWidth: 1.5) }
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(entry.count) digits entered")

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 18), count: 3), spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(height: 56)
                    } else {
                        Button {
                            Haptics.select()
                            if key == "delete" {
                                if !entry.isEmpty { entry.removeLast() }
                            } else if entry.count < VaultPIN.validLengths.upperBound {
                                entry.append(key)
                            }
                        } label: {
                            Group {
                                if key == "delete" {
                                    Image(systemName: "delete.left")
                                } else {
                                    Text(key)
                                }
                            }
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.pine)
                            .frame(width: 78, height: 56)
                            .background(key == "delete" ? Color.clear : Theme.stone, in: .rect(cornerRadius: Theme.radius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "delete" ? "Delete" : key)
                        .accessibilityIdentifier("pin.\(key)")
                    }
                }
            }

            Button(actionTitle, action: action)
                .buttonStyle(.primary)
                .disabled(!VaultPIN.isValid(entry))
                .accessibilityIdentifier("pin.submit")
        }
    }
}

/// Which photos weren't added and why. The ones that worked are already in the vault.
private struct ImportFailuresSheet: View {
    let failures: [VaultImportFailure]
    let addedCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(failures) { failure in
                        HStack(alignment: .top, spacing: 12) {
                            FailureThumbnail(id: failure.id)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.label)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.pine)
                                Text(failure.error.message)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .listRowBackground(Theme.stone)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("vault.failure")
                    }
                } header: {
                    Text(addedCount > 0
                         ? "\(counted(addedCount, "photo")) added. These weren't, and stay in Photos:"
                         : "These photos weren't added and stay in Photos:")
                } footer: {
                    Text("Nothing was deleted. You can try these again.")
                }
            }
            .brandList()
            .navigationTitle(failures.count == 1 ? "1 photo wasn't added" : "\(failures.count) photos weren't added")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
    }
}

private struct FailureThumbnail: View {
    let id: String

    var body: some View {
        Group {
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                AssetThumbnail(asset: asset)
            } else {
                Theme.hairline
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: Theme.thumbRadius))
        .accessibilityHidden(true)
    }
}
