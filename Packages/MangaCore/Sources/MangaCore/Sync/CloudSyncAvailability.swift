import Foundation

/// Whether this build can use iCloud, decided before touching CloudKit
/// (which stops the app when the iCloud entitlement is missing).
///
/// A build is iCloud-ready when its Info.plist has `MRCloudKitContainer`
/// set to an `iCloud.` container id (from the `MR_ICLOUD_CONTAINER` build
/// setting in project.yml) and, for development builds that carry a
/// provisioning profile, that profile lists the container. Builds without
/// the membership leave the setting empty, so sync stays off and nothing
/// else changes. See docs/ICLOUD.md.
public enum CloudSyncAvailability {
    public static let infoKey = "MRCloudKitContainer"
    static let containersEntitlement = "com.apple.developer.icloud-container-identifiers"

    public static func containerIdentifier(in bundle: Bundle = .main) -> String? {
        let provision = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return containerIdentifier(info: bundle.infoDictionary ?? [:], provisioningProfile: provision)
    }

    /// - Parameter provisioningProfile: the bundle's embedded.mobileprovision
    ///   (nil for App Store, TestFlight and unsigned simulator builds).
    public static func containerIdentifier(info: [String: Any], provisioningProfile: Data?) -> String? {
        guard let raw = info[infoKey] as? String else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.hasPrefix("iCloud."), id.count > 7, !id.contains("$(") else { return nil }
        if let provisioningProfile {
            guard let containers = entitledContainers(provisioningProfile: provisioningProfile),
                  containers.contains(id) else { return nil }
        }
        return id
    }

    /// The iCloud containers a provisioning profile allows. The profile is
    /// a signed blob with the plist in plain text inside.
    static func entitledContainers(provisioningProfile data: Data) -> [String]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data[start.lowerBound..<end.upperBound]
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else { return nil }
        return entitlements[containersEntitlement] as? [String] ?? []
    }
}
