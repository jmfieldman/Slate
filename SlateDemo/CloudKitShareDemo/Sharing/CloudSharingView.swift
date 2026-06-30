@preconcurrency import CloudKit
import SwiftUI
import UIKit

/// SwiftUI wrapper around the system **share sheet** for a note's `CKShare`.
///
/// This deliberately uses `UIActivityViewController` + `NSItemProvider`, *not*
/// `UICloudSharingController`. On iOS 17+ the older controller bridges into the
/// modern collaboration sheet when you tap "Share With More People / Invite with
/// Link", but it gives that sheet no sharing-option groups — so the link path
/// fails at runtime with:
///
///     CKErrorDomain Code=1 "No optionsGroups provided to addToCloudKitSharing"
///
/// `UICloudSharingController` exposes no way to supply `CKAllowedSharingOptions`
/// (its only knob, `availablePermissions`, is deprecated). The supported approach
/// — and what `UICloudSharingController`'s own deprecation note points to — is to
/// register the share on an `NSItemProvider` with explicit
/// `CKAllowedSharingOptions` and present it through the activity sheet. `.standard`
/// allows both "anyone with the link" and "only people you invite", at read-only
/// or read/write, so every option group is populated and the link path works.
///
/// The `CKShare` is already created and saved server-side by
/// `NotesStore.prepareShare(for:)` (via Slate), and it carries a title (required
/// for Mail/Messages), so we register the existing share directly.
struct CloudSharingView: UIViewControllerRepresentable {
    let invitation: ShareInvitation

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemProvider = NSItemProvider()
        itemProvider.registerCKShare(
            invitation.share,
            container: invitation.container,
            allowedSharingOptions: .standard
        )

        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])
        return UIActivityViewController(activityItemsConfiguration: configuration)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
