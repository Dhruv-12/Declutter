import Contacts
import Photos
import SwiftUI

/// First-run screen: explains what the app does and why it needs each permission.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        .padding(.top, 40)

                    VStack(spacing: 8) {
                        Text("Welcome to Declutter")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Find screenshots, large videos, similar photos and duplicate contacts, then clear them out. You review everything first.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        PermissionRow(
                            icon: "photo.on.rectangle", tint: .indigo,
                            title: "Photos",
                            reason: "To find screenshots, large videos and similar shots.",
                            state: photoState
                        ) {
                            Task { await model.requestPhotoAccess() }
                        }
                        PermissionRow(
                            icon: "person.2.fill", tint: .green,
                            title: "Contacts",
                            reason: "To find duplicate contacts you can merge.",
                            state: contactsState
                        ) {
                            Task { await model.requestContactsAccess() }
                        }
                    }

                    Label("Everything is scanned on this iPhone. Nothing is uploaded, and nothing is deleted without your approval.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Button(action: onFinish) {
                Text(hasAnyAccess ? "Continue" : "Skip for Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(24)
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
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .ask:
            Button("Allow", action: request)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel("Allowed")
        case .limited:
            Button("Limited") { SystemSettings.open() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
        case .denied:
            Button("Settings") { SystemSettings.open() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
