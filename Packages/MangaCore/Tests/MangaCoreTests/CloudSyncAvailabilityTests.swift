import XCTest
@testable import MangaCore

final class CloudSyncAvailabilityTests: XCTestCase {
    let id = "iCloud.com.rustedimac.MangaReader"

    func testOffUnlessTheBuildNamesAContainer() {
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: [:], provisioningProfile: nil))
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: ["MRCloudKitContainer": ""], provisioningProfile: nil))
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: ["MRCloudKitContainer": "$(MR_ICLOUD_CONTAINER)"],
                                                               provisioningProfile: nil))
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: ["MRCloudKitContainer": "com.example"], provisioningProfile: nil))
        XCTAssertEqual(CloudSyncAvailability.containerIdentifier(info: ["MRCloudKitContainer": id], provisioningProfile: nil), id)
    }

    func profile(containers: [String]?) -> Data {
        var entitlements: [String: Any] = ["application-identifier": "TEAM.com.rustedimac.MangaReader"]
        if let containers { entitlements["com.apple.developer.icloud-container-identifiers"] = containers }
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
        return Data([0x30, 0x82, 0x01, 0x00]) + plist + Data([0x00, 0xA0])
    }

    func testDevelopmentBuildsAlsoNeedTheContainerInTheirProfile() {
        let info = ["MRCloudKitContainer": id]
        XCTAssertEqual(CloudSyncAvailability.containerIdentifier(info: info, provisioningProfile: profile(containers: [id])), id)
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: info, provisioningProfile: profile(containers: nil)))
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: info, provisioningProfile: profile(containers: ["iCloud.other"])))
        XCTAssertNil(CloudSyncAvailability.containerIdentifier(info: info, provisioningProfile: Data("garbage".utf8)))
    }
}
