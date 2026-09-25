import Contacts
import ContactsUI
import Photos
import SwiftUI

/// Banners on the dashboard that explain missing or limited access and offer a fix.
struct PermissionBanners: View {
    @Environment(AppModel.self) private var model
    @State private var showContactPicker = false

    var body: some View {
        VStack(spacing: 12) {
            photoBanner
            contactsBanner
        }
        .modifier(ContactAccessPicker(isPresented: $showContactPicker) {
            model.refreshPermissions()
        })
    }

    @ViewBuilder private var photoBanner: some View {
        switch model.photoStatus {
        case .notDetermined:
            Banner(
                icon: "photo.on.rectangle", tint: .blue,
                title: "Allow photo access",
                message: "Needed to find screenshots, large videos and similar photos. Scanning happens only on this iPhone."
            ) {
                Button("Allow Photos") { Task { await model.requestPhotoAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        case .denied, .restricted:
            Banner(
                icon: "photo.badge.exclamationmark", tint: .red,
                title: "Photo access is off",
                message: "Turn on Photos access in Settings to scan screenshots, videos and similar photos."
            ) {
                Button("Open Settings") { SystemSettings.open() }
                    .buttonStyle(.borderedProminent)
            }
        case .limited:
            Banner(
                icon: "photo.badge.checkmark", tint: .orange,
                title: "Limited photo access",
                message: "Declutter can only see the photos you chose, so results only cover those."
            ) {
                Button("Choose More") { SystemSettings.presentLimitedPhotoPicker() }
                    .buttonStyle(.bordered)
                Button("Allow All") { SystemSettings.open() }
                    .buttonStyle(.borderedProminent)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var contactsBanner: some View {
        let status = model.contactsStatus
        if status == .notDetermined {
            Banner(
                icon: "person.crop.circle", tint: .blue,
                title: "Allow contacts access",
                message: "Needed to find duplicate contacts. Your contacts never leave this iPhone."
            ) {
                Button("Allow Contacts") { Task { await model.requestContactsAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if status == .denied || status == .restricted {
            Banner(
                icon: "person.crop.circle.badge.exclamationmark", tint: .red,
                title: "Contacts access is off",
                message: "Turn on Contacts access in Settings to find duplicate contacts."
            ) {
                Button("Open Settings") { SystemSettings.open() }
                    .buttonStyle(.borderedProminent)
            }
        } else if status.isLimited {
            Banner(
                icon: "person.crop.circle.badge.checkmark", tint: .orange,
                title: "Limited contacts access",
                message: "Declutter can only check the contacts you chose for duplicates."
            ) {
                Button("Choose More") { showContactPicker = true }
                    .buttonStyle(.bordered)
                Button("Allow All") { SystemSettings.open() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct Banner<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack { actions }
                .controlSize(.small)
                .padding(.leading, 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}

/// iOS 18 lets people share more contacts with an app that has limited access.
struct ContactAccessPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.contactAccessPicker(isPresented: $isPresented) { _ in onComplete() }
        } else {
            content
        }
    }
}
