// ClaudeStatus — ZCode menu bar indicator
// While ZCode works: animated Claude GIF (Thinking / RunningCommandOrResponding)
// plus small orange gerund text ("Brewing..."). When idle: green Claude symbol.
// Menu: manual animation overrides, per-model usage bars, current model.

import AppKit
import ImageIO
import UserNotifications
import Network
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Configuration

let stateDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".zcode-status")

let orange = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
let green = NSColor(srgbRed: 0x30 / 255.0, green: 0xA4 / 255.0, blue: 0x6C / 255.0, alpha: 1)
let menuWhite = NSColor.white
let menuDim = NSColor.white.withAlphaComponent(0.55)

let menuBarPoints: CGFloat = 18

/// If no activity file is touched for this long, fall back to idle so a crashed
/// session can't leave the animation running forever.
let stalenessLimit: TimeInterval = 20 * 60

/// How often the orange gerund text changes while working.
let wordRotation: TimeInterval = 4.0

/// Manual multi mode alternates animations on this period.
let multiSwitchInterval: TimeInterval = 7.0

/// Usage stats and model line refresh period.
let statsRefresh: TimeInterval = 10.0

/// Per-frame delay multiplier that speeds up the running-command GIF slightly.
let runningGifSpeedup: Double = 0.75

func todayLogPath() -> URL {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let name = "zcode-" + fmt.string(from: Date()) + ".jsonl"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zcode/cli/log").appendingPathComponent(name)
}

let gerunds = [
    "Accomplishing", "Actioning", "Actualizing", "Architecting", "Baking", "Beaming",
    "Beboppin'", "Befuddling", "Billowing", "Blanching", "Bloviating", "Boogieing",
    "Boondoggling", "Booping", "Bootstrapping", "Brewing", "Burrowing", "Calculating",
    "Canoodling", "Caramelizing", "Cascading", "Catapulting", "Cerebrating",
    "Channeling", "Channelling", "Choreographing", "Churning", "Clauding",
    "Coalescing", "Cogitating", "Combobulating", "Composing", "Computing",
    "Concocting", "Considering", "Contemplating", "Cooking", "Crafting", "Creating",
    "Crunching", "Crystallizing", "Cultivating", "Deciphering", "Deliberating",
    "Determining", "Dilly-dallying", "Discombobulating", "Doing", "Doodling",
    "Drizzling", "Ebbing", "Effecting", "Elucidating", "Embellishing", "Enchanting",
    "Envisioning", "Evaporating", "Fermenting", "Fiddle-faddling", "Finagling",
    "Flambéing", "Flibbertigibbeting", "Flowing", "Flummoxing", "Fluttering",
    "Forging", "Forming", "Frolicking", "Frosting", "Gallivanting", "Galloping",
    "Garnishing", "Generating", "Germinating", "Gitifying", "Grooving", "Gusting",
    "Harmonizing", "Hashing", "Hatching", "Herding", "Honking", "Hullaballooing",
    "Hyperspacing", "Ideating", "Imagining", "Improvising", "Incubating", "Inferring",
    "Infusing", "Ionizing", "Jitterbugging", "Julienning", "Kneading", "Leavening",
    "Levitating", "Lollygagging", "Manifesting", "Marinating", "Meandering",
    "Metamorphosing", "Misting", "Moonwalking", "Moseying", "Mulling", "Mustering",
    "Musing", "Nebulizing", "Nesting", "Noodling", "Nucleating", "Orbiting",
    "Orchestrating", "Osmosing", "Perambulating", "Percolating", "Perusing",
    "Philosophising", "Photosynthesizing", "Pollinating", "Pondering",
    "Pontificating", "Pouncing", "Precipitating", "Prestidigitating", "Processing",
    "Proofing", "Propagating", "Puttering", "Puzzling", "Quantumizing",
    "Razzle-dazzling", "Razzmatazzing", "Recombobulating", "Reticulating",
    "Roosting", "Ruminating", "Sautéing", "Scampering", "Schlepping", "Scurrying",
    "Seasoning", "Shenaniganing", "Shimmying", "Simmering", "Skedaddling",
    "Sketching", "Slithering", "Smooshing", "Sock-hopping", "Spelunking", "Spinning",
    "Sprouting", "Stewing", "Sublimating", "Swirling", "Swooping", "Symbioting",
    "Synthesizing", "Tempering", "Thinking", "Thundering", "Tinkering",
    "Triangulating", "Tomfoolering", "Topsy-turvying", "Transfiguring",
    "Transmuting", "Twisting", "Undulating", "Unfurling", "Unravelling", "Vibing",
    "Waddling", "Wandering", "Warping", "Whatchamacalliting", "Whirlpooling",
    "Whirring", "Whisking", "Wibbling", "Working", "Wrangling", "Zesting",
    "Zigzagging",
]

// MARK: - Asset loading

/// Locates the assets directory inside the app bundle, with a source-tree fallback.
let assetsDir: URL = {
    if let res = Bundle.main.resourceURL {
        let bundled = res.appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
    }
    return URL(fileURLWithPath: "~/Desktop/School/ZCode/claude-menubar/assets")
        .resolvingSymlinksInPath()
}()

struct GifAnimation {
    let frames: [NSImage]
    let delays: [TimeInterval]
}

/// Decodes a GIF into scaled frames with per-frame delays, sped up by `speed`.
func loadGif(url: URL, side: CGFloat, speed: Double = 1.0) -> GifAnimation? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let count = CGImageSourceGetCount(src)
    guard count > 0 else { return nil }
    var frames: [NSImage] = []
    var delays: [TimeInterval] = []
    for i in 0..<count {
        guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
        frames.append(NSImage(cgImage: cg, size: NSSize(width: side, height: side)))
        var delay = 0.1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any],
           let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any],
           let d = gif[kCGImagePropertyGIFDelayTime as String] as? Double {
            delay = d
        }
        delays.append(max(delay * speed, 0.02))
    }
    return GifAnimation(frames: frames, delays: delays)
}

/// Loads the Claude symbol SVG recolored green for the idle state.
func loadGreenIdleIcon(side: CGFloat) -> NSImage? {
    let svgURL = assetsDir.appendingPathComponent("Claude_AI_symbol.svg")
    guard var text = try? String(contentsOf: svgURL, encoding: .utf8) else { return nil }
    if let range = text.range(of: "fill=\"[^\"]*\"", options: .regularExpression) {
        text = text.replacingCharacters(in: range, with: "fill=\"#30A46C\"")
    }
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude_idle_green.svg")
    try? text.write(to: tmp, atomically: true, encoding: .utf8)
    guard let svg = NSImage(contentsOf: tmp) else { return nil }
    let icon = NSImage(size: NSSize(width: side, height: side))
    icon.lockFocus()
    svg.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    icon.unlockFocus()
    icon.isTemplate = false
    return icon
}

/// Fallback idle icon if SVG rendering ever fails: drawn green starburst.
func drawFallbackIdleIcon() -> NSImage {
    let px = Int(menuBarPoints * 2)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: menuBarPoints, height: menuBarPoints)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = menuBarPoints / 2
    let maxR = menuBarPoints / 2 - 1.0
    green.setStroke()
    for i in 0..<8 {
        let base = CGFloat(i) / 8.0 * 2 * .pi
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c + cos(base) * 2.0, y: c + sin(base) * 2.0))
        path.line(to: NSPoint(x: c + cos(base) * maxR, y: c + sin(base) * maxR))
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: menuBarPoints, height: menuBarPoints))
    image.addRepresentation(rep)
    image.isTemplate = false
    return image
}

// MARK: - State watcher

func mtime(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

enum WorkState: Equatable {
    case idle
    case thinking
    case runningTool
}

enum ManualMode: Int {
    case auto = 0
    case multi = 1
    case thinkingOnly = 2
    case runningOnly = 3
}

/// Newest activity file (thinking/tool, plus legacy "active") vs newest done file.
func currentWorkState() -> WorkState {
    let active = [stateDir.appendingPathComponent("thinking"),
                  stateDir.appendingPathComponent("tool"),
                  stateDir.appendingPathComponent("active")]
        .compactMap { mtime($0) }
        .max()
    guard let active, Date().timeIntervalSince(active) < stalenessLimit else {
        return .idle
    }
    if let done = mtime(stateDir.appendingPathComponent("done")), done > active {
        return .idle
    }
    let toolNewest = mtime(stateDir.appendingPathComponent("tool")) ?? .distantPast
    let thinkingNewest = max(mtime(stateDir.appendingPathComponent("thinking")) ?? .distantPast,
                             mtime(stateDir.appendingPathComponent("active")) ?? .distantPast)
    return toolNewest > thinkingNewest ? .runningTool : .thinking
}

// MARK: - Usage stats & current model (read from ZCode's local caches)

struct ModelBalance {
    var remaining: Int = 0
    var total: Int = 0
    var nextReset: Date?
    var percentLeft: Double {
        total > 0 ? Double(remaining) / Double(total) : 0
    }
}

/// ZCode's desktop app caches plan balance snapshots in its main window's
/// localStorage (leveldb). We scan those files for the newest snapshot JSON.
/// Key prefix changed in ZCode 3.14 (subscription-v2); the old one is kept as
/// a fallback for older installs.
let balanceKeyPrefixes = [
    "zcode:usage-entitlement:subscription-v2:account:zai-start-plan",
    "zcode:usage-entitlement:builtin:zai-start-plan",
]

let balanceStorageDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ZCode/session/Local Storage/leveldb")

func balanceSnapshot() -> [String: ModelBalance] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: balanceStorageDir.path) else { return [:] }

    var bestCachedAt: Int64 = 0
    var bestJSON: [String: Any]?
    for name in files where name.hasSuffix(".log") || name.hasSuffix(".ldb") {
        guard let raw = fm.contents(atPath: balanceStorageDir.appendingPathComponent(name).path) else { continue }
        let text = String(decoding: raw, as: UTF8.self)
        for prefix in balanceKeyPrefixes {
            var searchStart = text.startIndex
            while let keyRange = text.range(of: prefix, range: searchStart..<text.endIndex) {
                // The JSON blob follows the storage key (possibly with an
                // account-id suffix in between).
                guard let jsonStart = text.range(of: "{\"cachedAt\":", range: keyRange.upperBound..<text.endIndex) else { break }
                // Balanced-brace scan for the full snapshot object. Compressed
                // regions can corrupt this scan; json.loads below rejects the
                // broken ones, and a clean copy always exists in a newer file.
                var depth = 0
                var index = jsonStart.lowerBound
                var inString = false
                var escaped = false
                while index < text.endIndex {
                    let ch = text[index]
                    if escaped { escaped = false }
                    else if ch == "\\" && inString { escaped = true }
                    else if ch == "\"" { inString.toggle() }
                    else if !inString {
                        if ch == "{" { depth += 1 }
                        else if ch == "}" {
                            depth -= 1
                            if depth == 0 {
                                let jsonText = String(text[jsonStart.lowerBound...index])
                                if let obj = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
                                   let cachedAt = obj["cachedAt"] as? Int64, cachedAt > bestCachedAt {
                                    bestCachedAt = cachedAt
                                    bestJSON = obj
                                }
                                break
                            }
                        }
                    }
                    index = text.index(after: index)
                }
                searchStart = index > jsonStart.lowerBound ? index : keyRange.upperBound
            }
        }
    }

    guard let snapshot = bestJSON?["snapshot"] as? [String: Any],
           let quota = snapshot["quota"] as? [String: Any],
           let limits = quota["limits"] as? [[String: Any]] else { return [:] }

    var byModel: [String: ModelBalance] = [:]
    for limit in limits {
        guard let details = limit["usageDetails"] as? [[String: Any]] else { continue }
        let remaining = limit["remaining"] as? Int ?? 0
        let total = limit["number"] as? Int ?? 0
        let resetMs = limit["nextResetTime"] as? Int64 ?? 0
        let reset = resetMs > 0 ? Date(timeIntervalSince1970: Double(resetMs) / 1000) : nil
        for detail in details {
            guard let name = detail["displayName"] as? String else { continue }
            var bucket = byModel[name] ?? ModelBalance()
            bucket.remaining += remaining
            bucket.total += total
            if let reset, bucket.nextReset == nil || reset > bucket.nextReset! {
                bucket.nextReset = reset
            }
            byModel[name] = bucket
        }
    }
    return byModel
}

/// Model ids appear in several shapes across versions (`account:plan/NAME`,
/// `provider/cl/z-ai/glm-5.3-flash`, plain `NAME`); normalize to display names.
let knownModelNames = ["GLM-5.3-Flash", "GLM-5.3", "GLM-5-Turbo"]

func normalizeModelName(_ raw: String) -> String {
    var name = raw
    if let slash = name.lastIndex(of: "/") {
        name = String(name[name.index(after: slash)...])
    }
    if let colon = name.lastIndex(of: ":") {
        name = String(name[name.index(after: colon)...])
    }
    return knownModelNames.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
}

/// The model the current/last task is using. ZCode 3.14 removed model ids
/// from most log events, so the primary source is the usage db's latest
/// main_turn row (clean display name); the log is a fallback with growing
/// read windows for quiet tails.
func fetchCurrentModel() -> String {
    let dbModel = sqliteQuery("""
    SELECT model_id FROM model_usage WHERE query_source='main_turn'
    ORDER BY started_at DESC LIMIT 1;
    """).trimmingCharacters(in: .whitespacesAndNewlines)
    if !dbModel.isEmpty, !dbModel.hasPrefix("sqlite"), dbModel != "(null)" {
        return normalizeModelName(dbModel)
    }

    let url = todayLogPath()
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "unknown" }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    for window in [400_000, 2_000_000, UInt64.max] {
        let effective = min(size, window)
        try? handle.seek(toOffset: size - effective)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { continue }

        var fallback: String?
        for line in text.split(separator: "\n").reversed() {
            guard let modelRange = line.range(of: "\"model\":\"") else { continue }
            let afterQuote = line[modelRange.upperBound...]
            guard let end = afterQuote.firstIndex(of: "\"") else { continue }
            let normalized = normalizeModelName(String(afterQuote[..<end]))
            if line.contains("\"querySource\":\"main_turn\"") {
                return normalized
            }
            if fallback == nil { fallback = normalized }
        }
        if let fallback, window == 400_000 || fallback != "unknown" {
            return fallback
        }
    }
    return "unknown"
}

/// "resets in 6h 12m" style countdown; falls back to the date beyond 48h.
func formatReset(_ date: Date?) -> String {
    guard let date else { return "" }
    let interval = date.timeIntervalSinceNow
    if interval <= 0 { return "resets soon" }
    if interval < 3600 {
        return "resets in \(max(1, Int(interval) / 60))m"
    }
    if interval < 48 * 3600 {
        return "resets in \(Int(interval) / 3600)h \(Int(interval) % 3600 / 60)m"
    }
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    return "resets " + fmt.string(from: date)
}

/// Today's token totals per model from ZCode's sqlite db (read-only).
let usageDbPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".zcode/cli/db/db.sqlite").path

@discardableResult
func sqliteQuery(_ sql: String) -> String {
    runTool("/usr/bin/sqlite3", ["-readonly", usageDbPath, sql]).out
}

func fetchTokenUsage() -> [String: Int] {
    let cal = Calendar.current
    let midnight = cal.startOfDay(for: Date()).timeIntervalSince1970 * 1000
    let sql = """
    SELECT model_id, SUM(computed_total_tokens) FROM model_usage
    WHERE started_at >= \(Int(midnight))
      AND model_id IN ('GLM-5.3', 'GLM-5.3-Flash')
    GROUP BY model_id;
    """
    var result: [String: Int] = [:]
    for line in sqliteQuery(sql).split(separator: "\n") {
        let cols = line.split(separator: "|", omittingEmptySubsequences: false)
        guard cols.count == 2, let tokens = Int(cols[1]) else { continue }
        result[String(cols[0])] = tokens
    }
    return result
}

/// The finished chat's title, for finish notifications.
func sessionTitle(for sessionId: String) -> String? {
    let raw = sqliteQuery("SELECT title FROM session WHERE id='\(sessionId)';")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, !raw.hasPrefix("sqlite") else { return nil }
    let flat = raw.replacingOccurrences(of: "\n", with: " ")
    return flat.count > 34 ? String(flat.prefix(33)) + "…" : flat
}

/// The model that session last used, for credit reporting.
func sessionModel(for sessionId: String) -> String? {
    let raw = sqliteQuery("""
    SELECT model_id FROM model_usage WHERE session_id='\(sessionId)'
    ORDER BY started_at DESC LIMIT 1;
    """).trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty || raw.hasPrefix("sqlite") ? nil : raw
}

// MARK: - Launch at login

let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/com.reecedove.claudestatus.plist")

func isLaunchAtLoginEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentURL.path)
}

func setLaunchAtLogin(_ enabled: Bool) {
    let fm = FileManager.default
    let uid = getuid()
    if enabled {
        let appPath = Bundle.main.bundleURL.path
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.reecedove.claudestatus</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)/Contents/MacOS/ClaudeStatus</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        try? fm.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? plist.write(toFile: launchAgentURL.path, atomically: true, encoding: .utf8)
        let ctl = Process()
        ctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        ctl.arguments = ["bootstrap", "gui/\(uid)", launchAgentURL.path]
        try? ctl.run()
        ctl.waitUntilExit()
        if ctl.terminationStatus != 0 {
            // Already loaded from a previous install; kick it to the new binary.
            let kick = Process()
            kick.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kick.arguments = ["kickstart", "-k", "gui/\(uid)/com.reecedove.claudestatus"]
            try? kick.run()
        }
    } else {
        let ctl = Process()
        ctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        ctl.arguments = ["bootout", "gui/\(uid)/com.reecedove.claudestatus"]
        try? ctl.run()
        ctl.waitUntilExit()
        try? fm.removeItem(at: launchAgentURL)
    }
}

// MARK: - Notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Show banners even while the app is active.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

let notificationDelegate = NotificationDelegate()

func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.delegate = notificationDelegate
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    center.getNotificationSettings { settings in
        NSLog("ClaudeStatus notification auth status: \(settings.authorizationStatus.rawValue)")
    }
}

func sendNotification(title: String, body: String, identifier: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
        if let error {
            NSLog("ClaudeStatus notification error: \(error)")
            // macOS 26 rejects notifications from unsigned apps entirely, so
            // deliver via osascript (Apple-signed legacy path) instead.
            sendNotificationViaAppleScript(title: title, body: body)
        }
    }
}

/// Fallback delivery used when the app isn't properly signed.
func sendNotificationViaAppleScript(title: String, body: String) {
    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]
    try? proc.run()
}

/// One low-balance notification per model per day.
func dayStamp() -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt.string(from: Date())
}

// MARK: - Code Sleep (power assertions)

var sleepAssertionIDs: [IOPMAssertionID] = []

/// Holds idle-sleep and lid-close (clamshell) assertions. Lid-close prevention
/// is respected by macOS only while on AC power.
func acquireSleepAssertions() -> Bool {
    guard sleepAssertionIDs.isEmpty else { return true }
    var ids: [IOPMAssertionID] = []
    for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventSystemSleep] {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "ClaudeStatus Code Sleep" as CFString,
                                                 &id)
        if result == kIOReturnSuccess { ids.append(id) }
    }
    guard !ids.isEmpty else { return false }
    sleepAssertionIDs = ids
    return true
}

func releaseSleepAssertions() {
    for id in sleepAssertionIDs { IOPMAssertionRelease(id) }
    sleepAssertionIDs = []
}

func onACPower() -> Bool {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
        return false
    }
    for source in list {
        guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
            as? [String: Any],
            let state = desc[kIOPSPowerSourceStateKey] as? String else { continue }
        if state == kIOPSACPowerValue { return true }
    }
    return false
}

// Pausing other user apps with SIGSTOP while Code Sleep holds. Fully resumed on
// release; Finder/system apps and ZCode are always excluded.
let pauseExclusions: Set<String> = ["Finder", "Dock", "SystemUIServer", "ControlCenter",
                                    "Spotlight", "ZCode", "ClaudeStatus"]
var pausedPids: [pid_t] = []

func pauseOtherApps() {
    guard UserDefaults.standard.bool(forKey: "pauseOthers") else { return }
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        guard let name = app.localizedName, !pauseExclusions.contains(name) else { continue }
        guard !pausedPids.contains(app.processIdentifier) else { continue }
        if kill(app.processIdentifier, SIGSTOP) == 0 {
            pausedPids.append(app.processIdentifier)
        }
    }
}

func resumeOtherApps() {
    for pid in pausedPids { kill(pid, SIGCONT) }
    pausedPids.removeAll()
}

// MARK: - Phone hotspot auto-connect

let hotspotService = "ClaudeStatus Hotspot"

@discardableResult
func runTool(_ path: String, _ args: [String]) -> (exit: Int32, out: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do { try proc.run() } catch { return (-1, "\(error)") }
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
}

func wifiDevice() -> String? {
    let (_, out) = runTool("/usr/sbin/networksetup", ["-listallhardwareports"])
    let lines = out.split(separator: "\n").map(String.init)
    for (i, line) in lines.enumerated() where line.contains("Wi-Fi") {
        if i + 1 < lines.count, let dev = lines[i + 1].split(separator: ":").last {
            return dev.trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

func hotspotPassword(ssid: String) -> String? {
    let result = runTool("/usr/bin/security",
                         ["find-generic-password", "-s", hotspotService, "-a", ssid, "-w"])
    guard result.exit == 0 else { return nil }
    return result.out.split(separator: "\n").first.map(String.init)
}

func attemptHotspotConnect() {
    guard let ssid = UserDefaults.standard.string(forKey: "hotspotSSID"),
          let pass = hotspotPassword(ssid: ssid),
          let device = wifiDevice() else { return }
    let first = runTool("/usr/sbin/networksetup", ["-setairportnetwork", device, ssid, pass])
    if first.exit != 0 {
        let second = runTool("/usr/bin/sudo",
                             ["-n", "/usr/sbin/networksetup", "-setairportnetwork", device, ssid, pass])
        if second.exit != 0 {
            let key = "hotspotHint-\(dayStamp())"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                sendNotification(title: "Hotspot auto-connect failed",
                                 body: "networksetup needs admin rights on this Mac. Join \(ssid) once manually or grant sudo.",
                                 identifier: "hotspot-hint-\(dayStamp())")
            }
        }
    }
}

func promptHotspotConfig() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Phone Hotspot"
    alert.informativeText = "Enter your phone's hotspot name and password. ClaudeStatus will switch to it whenever internet drops (best with Code Sleep)."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    let ssidField = NSTextField(frame: NSRect(x: 0, y: 44, width: 240, height: 24))
    ssidField.placeholderString = "Hotspot name (SSID)"
    let passField = NSSecureTextField(frame: NSRect(x: 0, y: 8, width: 240, height: 24))
    passField.placeholderString = "Password"
    let stack = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 76))
    stack.addSubview(ssidField)
    stack.addSubview(passField)
    alert.accessoryView = stack
    if alert.runModal() == .alertFirstButtonReturn {
        let ssid = ssidField.stringValue.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(ssid, forKey: "hotspotSSID")
        if !ssid.isEmpty, !passField.stringValue.isEmpty {
            _ = runTool("/usr/bin/security",
                        ["add-generic-password", "-s", hotspotService, "-a", ssid,
                         "-w", passField.stringValue, "-U"])
        }
    }
}

// MARK: - Menu custom views

/// Rounded usage bar track with an orange fill fraction (red when running low).
final class UsageBarView: NSView {
    var fraction: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var warning = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.15).setFill()
        track.fill()
        guard fraction > 0 else { return }
        let w = max(bounds.height, bounds.width * min(fraction, 1) - 2)
        let fillRect = NSRect(x: 1, y: 1, width: w, height: bounds.height - 2)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: fillRect.height / 2, yRadius: fillRect.height / 2)
        (warning ? NSColor.systemRed : orange).setFill()
        fill.fill()
    }
}

func menuLabel(_ text: String, bold: Bool = false, color: NSColor = menuWhite,
               size: CGFloat = 11) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    field.textColor = color
    field.backgroundColor = .clear
    field.isBezeled = false
    field.isEditable = false
    field.isSelectable = false
    return field
}

/// One usage row: model name + "% left · reset" on top, bar, tokens line below.
/// NSMenu ignores a custom view's x-offset, so padding lives inside the view.
final class UsageRowView: NSView {
    static let pad: CGFloat = 16
    static let width: CGFloat = 320
    let nameLabel: NSTextField
    let statsLabel: NSTextField
    let tokenLabel: NSTextField
    let bar = UsageBarView(frame: NSRect(x: 0, y: 0, width: 320 - 32, height: 5))

    init(name: String) {
        nameLabel = menuLabel(name, bold: true)
        statsLabel = menuLabel("", color: menuDim, size: 10)
        tokenLabel = menuLabel("", color: menuDim, size: 9)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 56))
        let usable = Self.width - 2 * Self.pad
        nameLabel.frame = NSRect(x: Self.pad, y: 38, width: 112, height: 14)
        statsLabel.frame = NSRect(x: Self.pad + 116, y: 38, width: usable - 116, height: 14)
        statsLabel.alignment = .right
        bar.frame = NSRect(x: Self.pad, y: 25, width: usable, height: 5)
        tokenLabel.frame = NSRect(x: Self.pad, y: 8, width: usable, height: 12)
        addSubview(nameLabel)
        addSubview(statsLabel)
        addSubview(bar)
        addSubview(tokenLabel)
    }

    func render(balance: ModelBalance?, tokensToday: Int?) {
        guard let balance else {
            statsLabel.stringValue = ""
            tokenLabel.stringValue = ""
            bar.fraction = 0
            bar.warning = false
            return
        }
        let pct = Int(round(balance.percentLeft * 100))
        statsLabel.stringValue = "\(pct)% left · \(formatReset(balance.nextReset))"
        bar.fraction = CGFloat(balance.percentLeft)
        bar.warning = pct < 10
        if let tokensToday {
            tokenLabel.stringValue = "used \(formatTokens(tokensToday)) tok today"
        } else {
            tokenLabel.stringValue = ""
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

func formatTokens(_ n: Int) -> String {
    let d = Double(n)
    switch n {
    case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
    case 1_000...: return String(format: "%.1fk", d / 1_000)
    default: return "\(n)"
    }
}

/// Timers must run in `.common` mode or they freeze while the menu is open.
func commonTimer(_ interval: TimeInterval, repeats: Bool, _ block: @escaping () -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: repeats, block: { _ in block() })
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusMenuItem: NSMenuItem!

    var idleIcon: NSImage!
    var thinkingGif: GifAnimation?
    var runningGif: GifAnimation?

    var workState: WorkState = .idle        // what hooks say
    var display: WorkState = .idle          // what the button actually shows
    var manualMode: ManualMode = .auto
    var multiPhase: WorkState = .thinking
    var frameIndex = 0
    var frameTimer: Timer?
    var wordTimer: Timer?
    var pollTimer: Timer?
    var multiTimer: Timer?
    var statsTimer: Timer?
    var countdownLabel: NSTextField!
    var glmRow: UsageRowView!
    var flashRow: UsageRowView!
    var modelLabel: NSTextField!
    var countdown = 10

    var multiItem: NSMenuItem!
    var thinkingItem: NSMenuItem!
    var runningItem: NSMenuItem!
    var notifyItem: NSMenuItem!
    var launchItem: NSMenuItem!
    var sleepItem: NSMenuItem!
    var pauseItem: NSMenuItem!
    var hotspotItem: NSMenuItem!

    var codeSleepHolding = false
    var hotspotTimer: Timer?
    var lastHotspotAttempt = Date.distantPast
    var internetSatisfied = true
    let pathMonitor = NWPathMonitor()

    var lastBalances: [String: ModelBalance] = [:]
    var lastTokens: [String: Int] = [:]
    var currentModelName = ""
    let startTime = Date()
    var wasWorking = false

    // Keep the process out of App Nap — as an accessory app macOS throttles our
    // timers heavily, which made state changes show up seconds late.
    let napPrevention = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "ClaudeStatus: responsive ZCode status")

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        if UserDefaults.standard.object(forKey: "notifyOnFinish") == nil {
            UserDefaults.standard.set(true, forKey: "notifyOnFinish")
        }
        if UserDefaults.standard.bool(forKey: "notifyOnFinish") {
            requestNotificationPermission()
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.internetSatisfied = path.status == .satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "claudestatus-path"))
        refreshHotspotTimer()

        idleIcon = loadGreenIdleIcon(side: menuBarPoints) ?? drawFallbackIdleIcon()
        thinkingGif = loadGif(url: assetsDir.appendingPathComponent("Thinking.GIF"),
                              side: menuBarPoints)
        runningGif = loadGif(url: assetsDir.appendingPathComponent("RunningCommandOrResponding.gif"),
                             side: menuBarPoints, speed: runningGifSpeedup)

        if let button = statusItem.button {
            button.image = idleIcon
            button.image?.isTemplate = false
        }

        buildMenu()

        pollTimer = commonTimer(0.25, repeats: true) { [weak self] in
            self?.poll()
        }
        wordTimer = commonTimer(wordRotation, repeats: true) { [weak self] in
            self?.rotateWord()
        }
        statsTimer = commonTimer(1.0, repeats: true) { [weak self] in
            self?.statsTick()
        }
        poll()
        refreshStats()
    }

    func buildMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "ZCode: idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        multiItem = checkItem("Multi Animation Manual", action: #selector(toggleMulti))
        thinkingItem = checkItem("Thinking Animation Only", action: #selector(toggleThinkingOnly))
        runningItem = checkItem("Running Animation Only", action: #selector(toggleRunningOnly))
        notifyItem = checkItem("Notify When ZCode Finishes", action: #selector(toggleNotify))
        launchItem = checkItem("Launch at Login", action: #selector(toggleLaunch))
        sleepItem = checkItem("Code Sleep", action: #selector(toggleCodeSleep))
        pauseItem = checkItem("Pause Other Apps", action: #selector(togglePauseOthers))
        hotspotItem = checkItem("Auto-Connect Phone Hotspot", action: #selector(toggleHotspot))
        notifyItem.state = UserDefaults.standard.bool(forKey: "notifyOnFinish") ? .on : .off
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        sleepItem.state = UserDefaults.standard.bool(forKey: "codeSleepArmed") ? .on : .off
        pauseItem.state = UserDefaults.standard.bool(forKey: "pauseOthers") ? .on : .off
        hotspotItem.state = UserDefaults.standard.bool(forKey: "hotspotAutoConnect") ? .on : .off
        menu.addItem(multiItem)
        menu.addItem(thinkingItem)
        menu.addItem(runningItem)
        menu.addItem(notifyItem)
        menu.addItem(launchItem)
        menu.addItem(sleepItem)
        menu.addItem(pauseItem)
        menu.addItem(hotspotItem)
        menu.addItem(.separator())

        // Header: "Today's balance" + refresh countdown.
        let pad = UsageRowView.pad
        let width = UsageRowView.width
        let header = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 34))
        let title = menuLabel("Today's balance", bold: true)
        title.frame = NSRect(x: pad, y: 18, width: 140, height: 14)
        countdownLabel = menuLabel("Refreshing stats in 10s", color: menuDim, size: 9)
        countdownLabel.frame = NSRect(x: pad, y: 4, width: width - 2 * pad, height: 11)
        header.addSubview(title)
        header.addSubview(countdownLabel)
        menu.addItem(item(withView: header))

        glmRow = UsageRowView(name: "GLM-5.3")
        flashRow = UsageRowView(name: "GLM-5.3-Flash")
        menu.addItem(item(withView: glmRow))
        menu.addItem(item(withView: flashRow))

        let modelView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        let modelTitle = menuLabel("Current model", bold: true)
        modelTitle.frame = NSRect(x: pad, y: 14, width: width - 2 * pad, height: 14)
        modelLabel = menuLabel("…", color: orange, size: 10)
        modelLabel.frame = NSRect(x: pad, y: 1, width: width - 2 * pad, height: 12)
        modelView.addSubview(modelTitle)
        modelView.addSubview(modelLabel)
        menu.addItem(item(withView: modelView))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit ClaudeStatus",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func checkItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = .off
        return item
    }

    func item(withView view: NSView) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        item.isEnabled = false
        return item
    }

    // MARK: manual mode toggles

    @objc func toggleMulti() { setManual(manualMode == .multi ? .auto : .multi) }
    @objc func toggleThinkingOnly() { setManual(manualMode == .thinkingOnly ? .auto : .thinkingOnly) }
    @objc func toggleRunningOnly() { setManual(manualMode == .runningOnly ? .auto : .runningOnly) }

    @objc func toggleNotify() {
        let on = notifyItem.state != .on
        notifyItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "notifyOnFinish")
        if on {
            requestNotificationPermission()
            // Immediate test so the user can confirm delivery works.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                sendNotification(title: "ClaudeStatus test",
                                 body: "If you can read this, finish notifications are working.",
                                 identifier: "test-\(Int(Date().timeIntervalSince1970))")
            }
        }
    }

    @objc func toggleLaunch() {
        let on = launchItem.state != .on
        setLaunchAtLogin(on)
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    @objc func toggleCodeSleep() {
        let on = sleepItem.state != .on
        sleepItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "codeSleepArmed")
        if !on { releaseCodeSleep() }
    }

    @objc func togglePauseOthers() {
        let on = pauseItem.state != .on
        pauseItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "pauseOthers")
        if !on { resumeOtherApps() }
    }

    @objc func toggleHotspot() {
        let on = hotspotItem.state != .on
        hotspotItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "hotspotAutoConnect")
        if on, UserDefaults.standard.string(forKey: "hotspotSSID") == nil {
            promptHotspotConfig()
        }
        refreshHotspotTimer()
    }

    /// Holds sleep-prevention assertions exactly while ZCode is working.
    func updateCodeSleep() {
        let armed = UserDefaults.standard.bool(forKey: "codeSleepArmed")
        let shouldHold = armed && workState != .idle
        if shouldHold && !codeSleepHolding {
            if acquireSleepAssertions() {
                codeSleepHolding = true
                pauseOtherApps()
            }
        } else if !shouldHold && codeSleepHolding {
            releaseCodeSleep()
        }
        if codeSleepHolding {
            statusMenuItem.title = "ZCode: working · code sleep"
                + (onACPower() ? "" : " · plug in for lid")
        }
    }

    func releaseCodeSleep() {
        guard codeSleepHolding else { return }
        releaseSleepAssertions()
        resumeOtherApps()
        codeSleepHolding = false
    }

    func refreshHotspotTimer() {
        let armed = UserDefaults.standard.bool(forKey: "hotspotAutoConnect")
        if armed && hotspotTimer == nil {
            hotspotTimer = commonTimer(10, repeats: true) { [weak self] in
                self?.hotspotTick()
            }
        } else if !armed, let timer = hotspotTimer {
            timer.invalidate()
            hotspotTimer = nil
        }
    }

    /// Switches to the hotspot after internet has been down for consecutive checks.
    func hotspotTick() {
        guard !internetSatisfied else { return }
        guard Date().timeIntervalSince(lastHotspotAttempt) > 60 else { return }
        lastHotspotAttempt = Date()
        attemptHotspotConnect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseCodeSleep()
    }

    func setManual(_ mode: ManualMode) {
        manualMode = mode
        multiItem.state = mode == .multi ? .on : .off
        thinkingItem.state = mode == .thinkingOnly ? .on : .off
        runningItem.state = mode == .runningOnly ? .on : .off

        multiTimer?.invalidate()
        if mode == .multi {
            multiPhase = .thinking
            multiTimer = commonTimer(multiSwitchInterval, repeats: true) { [weak self] in
                guard let self else { return }
                self.multiPhase = self.multiPhase == .thinking ? .runningTool : .thinking
                self.applyDisplay(self.multiPhase)
            }
        }
        applyDisplay(desiredDisplay())
    }

    /// The animation the button should show right now.
    func desiredDisplay() -> WorkState {
        switch manualMode {
        case .auto: return workState
        case .multi: return multiPhase
        case .thinkingOnly: return .thinking
        case .runningOnly: return .runningTool
        }
    }

    // MARK: animation driver

    func scheduleNextFrame(after delay: TimeInterval) {
        frameTimer?.invalidate()
        frameTimer = commonTimer(delay, repeats: false) { [weak self] in
            self?.advanceFrame()
        }
    }

    func advanceFrame() {
        guard display != .idle, let button = statusItem.button else { return }
        let gif = display == .runningTool ? runningGif : thinkingGif
        guard let gif, !gif.frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % gif.frames.count
        button.image = gif.frames[frameIndex]
        scheduleNextFrame(after: gif.delays[frameIndex])
    }

    func applyDisplay(_ newDisplay: WorkState) {
        guard newDisplay != display || frameTimer == nil else { return }
        let old = display
        display = newDisplay
        frameIndex = 0
        guard let button = statusItem.button else { return }

        switch newDisplay {
        case .idle:
            frameTimer?.invalidate()
            button.attributedTitle = NSAttributedString(string: "")
            button.image = idleIcon
        case .thinking, .runningTool:
            let gif = newDisplay == .runningTool ? runningGif : thinkingGif
            guard let gif, !gif.frames.isEmpty else { return }
            if old == .idle { rotateWord() }
            button.image = gif.frames[0]
            scheduleNextFrame(after: gif.delays[0])
        }

        // Status line reflects hook state + manual override.
        switch manualMode {
        case .auto:
            statusMenuItem.title = workState == .idle ? "ZCode: idle"
                : (workState == .runningTool ? "ZCode: running…" : "ZCode: thinking…")
        case .multi: statusMenuItem.title = "ZCode: manual (multi)"
        case .thinkingOnly: statusMenuItem.title = "ZCode: manual (thinking)"
        case .runningOnly: statusMenuItem.title = "ZCode: manual (running)"
        }
    }

    func rotateWord() {
        guard display != .idle, let button = statusItem.button else { return }
        let word = gerunds.randomElement()! + "..."
        button.attributedTitle = NSAttributedString(string: word, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: orange,
        ])
    }

    func poll() {
        workState = currentWorkState()
        if wasWorking && workState == .idle,
           Date().timeIntervalSince(startTime) > 5,
           UserDefaults.standard.bool(forKey: "notifyOnFinish") {
            let body = finishedChatSummary()
            sendNotification(title: "ZCode is done ✓", body: body,
                             identifier: "finish-\(Int(Date().timeIntervalSince1970))")
        }
        wasWorking = workState != .idle
        applyDisplay(desiredDisplay())
        updateCodeSleep()
    }

    /// "Chat title · used N% of <model> credit" for the chat that just finished.
    func finishedChatSummary() -> String {
        var parts: [String] = []
        var model: String?
        let sessionFile = stateDir.appendingPathComponent("finished")
        if let sessionId = (try? String(contentsOf: sessionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           sessionId.hasPrefix("sess_") {
            if let title = sessionTitle(for: sessionId) {
                parts.append("“\(title)”")
            }
            model = sessionModel(for: sessionId)
        }
        let usedModel = model ?? (currentModelName.isEmpty ? nil : currentModelName)
        if let usedModel, let balance = lastBalances[usedModel], balance.total > 0 {
            let used = Int(round((1 - balance.percentLeft) * 100))
            parts.append("used \(used)% of \(usedModel) credit today")
        } else if let usedModel {
            parts.append(usedModel)
        }
        return parts.isEmpty ? "The chat finished." : parts.joined(separator: " · ")
    }

    // MARK: stats

    func statsTick() {
        countdown -= 1
        if countdown <= 0 {
            countdown = Int(statsRefresh)
            refreshStats()
        }
        countdownLabel.stringValue = "Refreshing stats in \(countdown)s"
        renderRows()
    }

    func renderRows() {
        glmRow.render(balance: lastBalances["GLM-5.3"], tokensToday: lastTokens["GLM-5.3"])
        flashRow.render(balance: lastBalances["GLM-5.3-Flash"], tokensToday: lastTokens["GLM-5.3-Flash"])
    }

    func refreshStats() {
        lastBalances = balanceSnapshot()
        lastTokens = fetchTokenUsage()
        checkLowBalance()
        renderRows()
        currentModelName = fetchCurrentModel()
        modelLabel.stringValue = currentModelName
        let glm = lastBalances["GLM-5.3"].map { "\(Int(round($0.percentLeft * 100)))%" } ?? "none"
        let flash = lastBalances["GLM-5.3-Flash"].map { "\(Int(round($0.percentLeft * 100)))%" } ?? "none"
        NSLog("ClaudeStatus stats: GLM-5.3=%@ flash=%@ model=%@", glm, flash, currentModelName)
    }

    func checkLowBalance() {
        guard UserDefaults.standard.bool(forKey: "notifyOnFinish") else { return }
        for (name, balance) in lastBalances {
            guard balance.total > 0, balance.percentLeft < 0.10 else { continue }
            let key = "lowWarned-\(name)-\(dayStamp())"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            UserDefaults.standard.set(true, forKey: key)
            let pct = Int(round(balance.percentLeft * 100))
            sendNotification(title: "\(name) is running low",
                             body: "Only \(pct)% of today's allowance is left.",
                             identifier: "low-\(name)-\(dayStamp())")
        }
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
