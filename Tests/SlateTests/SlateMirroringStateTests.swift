import CloudKit
import CoreData
import Foundation
import Testing
@testable import Slate

@Suite
struct SlateMirroringStateTests {
    @Test(arguments: [
        (CKAccountStatus.available, SlateAccountStatus.available),
        (CKAccountStatus.noAccount, SlateAccountStatus.unavailable),
        (CKAccountStatus.temporarilyUnavailable, SlateAccountStatus.unavailable),
        (CKAccountStatus.restricted, SlateAccountStatus.restricted),
        (CKAccountStatus.couldNotDetermine, SlateAccountStatus.couldNotDetermine),
    ])
    func mapsKnownCloudKitAccountStatuses(
        cloudKitStatus: CKAccountStatus,
        slateStatus: SlateAccountStatus
    ) {
        #expect(SlateAccountStatus(cloudKitStatus: cloudKitStatus) == slateStatus)
    }

    @Test
    func mapsUnknownCloudKitAccountStatusToCouldNotDetermine() throws {
        let futureStatus = try #require(CKAccountStatus(rawValue: 999))

        #expect(SlateAccountStatus(cloudKitStatus: futureStatus) == .couldNotDetermine)
    }

    @Test
    func neutralInitializerUsesLocalModeDefaults() {
        let state = SlateMirroringState()

        #expect(state.accountStatus == .unavailable)
        #expect(!state.isImporting)
        #expect(!state.isMerging)
        #expect(state.lastImportError == nil)
    }

    @Test
    func localSlateExposesNeutralMirroringPropertiesDirectly() {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)

        #expect(slate.accountStatus == .unavailable)
        #expect(!slate.isImporting)
        #expect(!slate.isMerging)
        #expect(slate.lastImportError == nil)
    }
}
