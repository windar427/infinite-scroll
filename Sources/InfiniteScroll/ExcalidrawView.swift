import AppKit
import SwiftUI
import WebKit

struct ExcalidrawView: NSViewRepresentable {
    let excalidrawID: UUID
    @Binding var text: String
    var fontSize: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "excalidraw")
        config.userContentController = userContent
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.isHidden = false

        context.coordinator.webView = webView
        context.coordinator.excalidrawID = excalidrawID

        ExcalidrawViewRegistry.shared.register(id: excalidrawID, view: webView)

        let html = Self.buildHTML(initialData: text)
        // Load with the Excalidraw resources dir as baseURL so relative <script src>
        // tags resolve to the vendored UMD bundles. Granting read access to that dir
        // also lets WKWebView fetch them without tripping the file:// same-origin rules.
        let resourcesDir = Self.excalidrawResourcesURL()
        webView.loadHTMLString(html, baseURL: resourcesDir)

        return webView
    }

    /// URL of the directory containing vendored Excalidraw/React UMD bundles.
    /// Uses `Bundle.module` (SwiftPM-generated) so it works both in `swift run`
    /// and inside a packaged `.app`.
    static func excalidrawResourcesURL() -> URL {
        if let url = Bundle.module.url(forResource: "Excalidraw", withExtension: nil) {
            return url
        }
        // Fallback: bundle root. Should not hit this in practice — if it does,
        // the script tags will 404 and the WebView will show its default blank page.
        return Bundle.module.bundleURL
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // If the text binding changed externally (e.g. from persistence restore),
        // push the new data into the webview. The coordinator tracks the last
        // value it sent to avoid echoing its own saves back.
        let coord = context.coordinator
        if text != coord.lastSavedText && !text.isEmpty {
            coord.lastSavedText = text
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            nsView.evaluateJavaScript("if(window.setExcalidrawData) window.setExcalidrawData('\(escaped)');", completionHandler: nil)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        if let id = coordinator.excalidrawID {
            ExcalidrawViewRegistry.shared.unregister(id: id)
        }
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "excalidraw")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        var text: Binding<String>
        weak var webView: WKWebView?
        var excalidrawID: UUID?
        var lastSavedText: String = ""
        private var debounceWorkItem: DispatchWorkItem?

        init(text: Binding<String>) {
            self.text = text
        }

        deinit {
            if let id = excalidrawID {
                ExcalidrawViewRegistry.shared.unregister(id: id)
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                    didReceive message: WKScriptMessage) {
            guard message.name == "excalidraw",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            if type == "dataSave", let json = body["data"] as? String {
                // Debounce: wait 1 second after the last change
                debounceWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.lastSavedText = json
                    self.text.wrappedValue = json
                }
                debounceWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
            }
        }
    }

    // MARK: - HTML template

    static func buildHTML(initialData: String) -> String {
        let escapedData = initialData
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body, #root { width: 100%; height: 100%; overflow: hidden; }
          body { background: #1e1e24; }
          /* Hide Excalidraw's top bar items we don't need */
          .excalidraw .main-menu-trigger { display: none !important; }
        </style>
        </head>
        <body>
        <div id="root"></div>
        <script src="react.production.min.js"></script>
        <script src="react-dom.production.min.js"></script>
        <script src="excalidraw.production.min.js"></script>
        <script>
        (function() {
          const initialDataJSON = `\(escapedData)`;
          let initialData = null;
          if (initialDataJSON && initialDataJSON.trim().length > 0) {
            try {
              initialData = JSON.parse(initialDataJSON);
            } catch(e) {
              console.warn('Failed to parse initial Excalidraw data:', e);
            }
          }

          let excalidrawAPI = null;

          // Debounced onChange: sends data to Swift after 1s of inactivity
          let debounceTimer = null;
          function onChangeHandler(elements, appState) {
            if (debounceTimer) clearTimeout(debounceTimer);
            debounceTimer = setTimeout(function() {
              try {
                const data = JSON.stringify({
                  elements: elements,
                  appState: {
                    viewBackgroundColor: appState.viewBackgroundColor,
                    currentItemStrokeColor: appState.currentItemStrokeColor,
                    currentItemBackgroundColor: appState.currentItemBackgroundColor,
                    theme: appState.theme
                  }
                });
                window.webkit.messageHandlers.excalidraw.postMessage({
                  type: 'dataSave',
                  data: data
                });
              } catch(e) {
                console.error('Failed to serialize Excalidraw data:', e);
              }
            }, 1000);
          }

          // Function for Swift to push data into the component
          window.setExcalidrawData = function(jsonStr) {
            if (!excalidrawAPI) return;
            try {
              const data = JSON.parse(jsonStr);
              if (data.elements) {
                excalidrawAPI.updateScene({
                  elements: data.elements,
                  appState: data.appState || {}
                });
              }
            } catch(e) {
              console.warn('setExcalidrawData parse error:', e);
            }
          };

          const App = React.createElement(
            ExcalidrawLib.Excalidraw,
            {
              theme: 'dark',
              initialData: initialData ? {
                elements: initialData.elements || [],
                appState: Object.assign(
                  { theme: 'dark', viewBackgroundColor: '#1e1e24' },
                  initialData.appState || {}
                )
              } : {
                appState: { theme: 'dark', viewBackgroundColor: '#1e1e24' }
              },
              onChange: onChangeHandler,
              excalidrawAPI: function(api) { excalidrawAPI = api; },
              UIOptions: {
                canvasActions: {
                  loadScene: false,
                  export: false,
                  saveAsImage: false
                }
              }
            }
          );

          const root = ReactDOM.createRoot(document.getElementById('root'));
          root.render(App);
        })();
        </script>
        </body>
        </html>
        """
    }
}
