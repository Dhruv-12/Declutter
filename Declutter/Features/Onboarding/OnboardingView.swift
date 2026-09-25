import Contacts
import Photos
import SwiftUI

/// First-run screen: explains what the app does and why it needs each permission.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing * 2) {
                Image("Logo")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(.rect(cornerRadius: 22))
                    .accessibilityHidden(true)
                    .padding(.top, 48)

                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    Text("Give your iPhone some breathing room")
                        .font(.heading(.largeTitle))
                        .foregroundStyle(Theme.pine)
                    Text("Declutter finds screenshots, large videos, similar photos and duplicate contacts. You check everything before anything is removed.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                }

                VStack(spacing: Theme.gap + 4) {
                    PermissionRow(
                        icon: "photo.on.rectangle",
                        tint: Theme.lake,
                        title: "Photos",
                        reason: "To find screenshots, large videos and similar shots.",
                        state: photoState
                    ) {
                        Task { await model.requestPhotoAccess() }
                    }
                    PermissionRow(
                        icon: "person.2.fill",
                        tint: Theme.teal,
                        title: "Contacts",
                        reason: "To find duplicate contacts you can merge.",
                        state: contactsState
                    ) {
                        Task { await model.requestContactsAccess() }
                    }
                }

                Label("Everything is checked on this iPhone. Nothing is uploaded, and nothing is deleted without your approval.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, Theme.page)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            Button(hasAnyAccess ? "Continue" : "Skip for now", action: onFinish)
                .buttonStyle(hasAnyAccess ? .primary : .secondary)
                .padding(.horizontal, Theme.page)
                .padding(.vertical, 12)
                .background(Theme.mist.ignoresSafeArea())
        }
    }

    private var hasAnyAccess: Bool {
        model.photoStatus.canRead || model.contactsStatus.canRead
    }

    private var photoState: PermissionRow.State {
        switch model.photoStatus {
        case .notDetermined: .ask
        case .authorized: .granted
        case .limited: .limited
        default: .denied
        }
    }

    private var contactsState: PermissionRow.State {
        let status = model.contactsStatus
        if status == .notDetermined { return .ask }
        if status == .authorized { return .granted }
        if status.isLimited { return .limited }
        return .denied
    }
}

struct PermissionRow: View {
    enum State { case ask, granted, limited, denied }

    let icon: String
    let tint: Color
    let title: String
    let reason: String
    let state: State
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .tintedCircle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                Text(stateText ?? reason)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .card()
    }

    private var stateText: String? {
        switch state {
        case .ask, .granted: nil
        case .limited: "Only the items you picked. You can allow more in Settings."
        case .denied: "Turned off. You can turn it on in Settings."
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .ask:
            Button("Allow", action: request)
                .buttonStyle(.compact(.primary))
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.mint)
                .accessibilityLabel("Allowed")
        case .limited, .denied:
            Button("Settings") { SystemSettings.open() }
                .buttonStyle(.compact(.onCard))
        }
    }
}
