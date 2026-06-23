import AppKit

/// Experimental access to the private CoreGraphics / SkyLight "CGS" Space APIs,
/// used to read and *attempt* to set Mission Control desktop (Space) names.
///
/// Everything here is undocumented and resolved at runtime via `dlsym`, so if a
/// symbol is missing on a given macOS the feature reports "unavailable" instead
/// of failing to launch. Honesty note: even when the set-name call succeeds at
/// the CGS level, the *visible* label in Mission Control is drawn by the Dock and
/// may not refresh until the Dock relaunches (or at all on newer macOS). We read
/// the name back after setting so the UI can tell the truth about what happened.
enum SpaceManager {

    // C function signatures for the private symbols we try to resolve.
    private typealias MainConnFn   = @convention(c) () -> Int32
    private typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyNameFn   = @convention(c) (Int32, UInt64) -> Unmanaged<CFString>?
    private typealias SetNameFn    = @convention(c) (Int32, UInt64, CFString) -> Int32

    /// RTLD_DEFAULT searches every already-loaded image for the symbol.
    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = UnsafeMutableRawPointer(bitPattern: -2),  // RTLD_DEFAULT
              let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let mainConn    = sym("CGSMainConnectionID", as: MainConnFn.self)
    private static let copyDisplays = sym("CGSCopyManagedDisplaySpaces", as: CopyDisplays.self)
    private static let copyNameFn  = sym("CGSSpaceCopyName", as: CopyNameFn.self)
    private static let setNameFn   = sym("CGSSpaceSetName", as: SetNameFn.self)

    /// Whether we can at least enumerate spaces.
    static var canEnumerate: Bool { mainConn != nil && copyDisplays != nil }
    /// Whether the (riskier) set-name symbol resolved.
    static var canRename: Bool { mainConn != nil && setNameFn != nil }

    private static var connection: Int32? { mainConn?() }

    struct Space: Identifiable {
        let id: UInt64
        let display: String
        let index: Int          // 1-based position within its display
        let isCurrent: Bool
        var name: String?
    }

    /// Enumerate every Space across all displays, in order, with any CGS-level
    /// name already assigned.
    static func spaces() -> [Space] {
        guard let cid = connection, let copyDisplays,
              let displays = copyDisplays(cid)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        var result: [Space] = []
        for display in displays {
            let displayID = (display["Display Identifier"] as? String) ?? "Main"
            let currentDict = display["Current Space"] as? [String: Any]
            let currentID = number(currentDict?["ManagedSpaceID"]) ?? number(currentDict?["id64"])
            let spaceDicts = (display["Spaces"] as? [[String: Any]]) ?? []

            var index = 0
            for space in spaceDicts {
                guard let sid = number(space["ManagedSpaceID"]) ?? number(space["id64"]) else { continue }
                index += 1
                result.append(Space(id: sid,
                                    display: displayID,
                                    index: index,
                                    isCurrent: sid == currentID,
                                    name: name(of: sid)))
            }
        }
        return result
    }

    static func name(of spaceID: UInt64) -> String? {
        guard let cid = connection, let copyNameFn,
              let cf = copyNameFn(cid, spaceID)?.takeRetainedValue() else { return nil }
        let value = cf as String
        return value.isEmpty ? nil : value
    }

    static func currentSpaceID() -> UInt64? {
        spaces().first(where: { $0.isCurrent })?.id
    }

    /// Attempt to set a Space's name. Returns true only if a read-back confirms
    /// the name actually took.
    @discardableResult
    static func setName(_ name: String, for spaceID: UInt64) -> Bool {
        guard let cid = connection, let setNameFn else { return false }
        _ = setNameFn(cid, spaceID, name as CFString)
        return self.name(of: spaceID) == name
    }

    /// Relaunch the Dock so Mission Control re-reads Space names. Intrusive, so
    /// it's only ever triggered by an explicit user action.
    static func relaunchDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    private static func number(_ any: Any?) -> UInt64? {
        (any as? NSNumber)?.uint64Value
    }
}
