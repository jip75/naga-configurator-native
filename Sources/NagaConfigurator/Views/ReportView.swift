import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Report a Bug or Idea" — its own small window (Help menu + About tab button). POSTs to
/// mkrlab.io/api/naga-lhm-report, which emails the owner via Resend. App + macOS versions ride
/// along automatically; the screenshot is optional (1-click capture of the main window, or drop
/// any image file onto the preview well).
struct ReportView: View {
    enum Kind: String, CaseIterable { case bug, idea }
    enum SendState: Equatable { case idle, sending, sent, failed(String) }

    @State private var kind: Kind = .bug
    @State private var message = ""
    @State private var email = ""
    @State private var screenshot: NSImage?
    @State private var state: SendState = .idle
    @State private var dropHover = false

    static let endpoint = URL(string: ProcessInfo.processInfo.environment["NAGA_REPORT_URL"] ?? "https://mkrlab.io/api/naga-lhm-report")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $kind) {
                Text("Bug").tag(Kind.bug)
                Text("Idea").tag(Kind.idea)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(kind == .bug ? "What happened, and what did you expect?" : "What would make this better?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.muted)

            TextEditor(text: $message)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120)
                .background(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(8)

            TextField("Your email (optional — only if you want a reply)", text: $email)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(8)

            screenshotWell

            Text("Sends: your message, app \(appVersion), macOS \(osVersion)\(screenshot != nil ? ", the screenshot" : "")\(email.isEmpty ? "" : ", your email"). Nothing else.")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                statusText
                Spacer()
                Button(state == .sending ? "Sending…" : "Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || state == .sending)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.panel)
    }

    @ViewBuilder private var statusText: some View {
        switch state {
        case .sent: Text("Sent — thank you!").foregroundColor(Theme.accentText).font(.system(size: 12, weight: .semibold))
        case .failed(let why): Text(why).foregroundColor(.red).font(.system(size: 12)).lineLimit(2)
        default: EmptyView()
        }
    }

    private var screenshotWell: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(dropHover ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1, dash: screenshot == nil ? [4] : []))
                if let img = screenshot {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    Text("Drop an image").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            }
            .frame(width: 120, height: 80)
            .onDrop(of: [.fileURL, .image], isTargeted: $dropHover, perform: handleDrop)

            VStack(alignment: .leading, spacing: 6) {
                Button("Capture App Window") { screenshot = Self.captureMainWindow() }
                if screenshot != nil {
                    Button("Remove Screenshot") { screenshot = nil }
                }
            }
            .font(.system(size: 12))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        if p.canLoadObject(ofClass: NSImage.self) {
            _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage { DispatchQueue.main.async { screenshot = img } }
            }
            return true
        }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url, let img = NSImage(contentsOf: url) { DispatchQueue.main.async { screenshot = img } }
        }
        return true
    }

    /// Renders the app's own main window (not the screen) — no Screen Recording permission needed,
    /// and it can never capture anything outside this app.
    static func captureMainWindow() -> NSImage? {
        guard let window = NSApp.windows.first(where: { $0.title == "Naga Configurator" && $0.isVisible }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    /// JPEG, longest side ≤ 1600px — keeps the request well under the route's ~2.6 MB cap.
    static func jpegBase64(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1600 / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.base64EncodedString()
    }

    private func send() {
        state = .sending
        var body: [String: Any] = [
            "kind": kind.rawValue,
            "message": message,
            "email": email.trimmingCharacters(in: .whitespaces),
            "appVersion": appVersion,
            "osVersion": osVersion,
        ]
        if let img = screenshot, let b64 = Self.jpegBase64(img) {
            body["screenshot"] = b64
            body["screenshotType"] = "jpg"
        }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                if code == 200, json?["ok"] as? Bool == true {
                    state = .sent
                    message = ""; screenshot = nil
                } else if let err {
                    state = .failed("Couldn't reach the server: \(err.localizedDescription)")
                } else {
                    state = .failed(json?["message"] as? String ?? "Send failed (HTTP \(code)). Try again in a bit.")
                }
            }
        }.resume()
    }
}
