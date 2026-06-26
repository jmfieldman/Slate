extension Slate {
    public var sharing: SlateSharing {
        get throws {
            try makeSharingFacade()
        }
    }
}
