import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("📱 [BidirectionalShareExt] viewDidLoad called")
        
        // Hide the UI to make it seamless
        self.view.isHidden = true
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        
        // Process the shared content and navigate to main app
        DispatchQueue.main.async {
            self.handleSharedContent()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📱 [BidirectionalShareExt] viewDidAppear called")
        
        // Close extension immediately to avoid UI issues
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    override func isContentValid() -> Bool {
        return true
    }
    
    override func didSelectPost() {
        print("📱 [BidirectionalShareExt] didSelectPost called")
        handleSharedContent()
    }
    
    override func configurationItems() -> [Any]! {
        return []
    }
    
    private func handleSharedContent() {
        guard let extensionContext = extensionContext else {
            print("❌ [BidirectionalShareExt] No extension context")
            closeShareExtension()
            return
        }
        
        print("🔍 [BidirectionalShareExt] Starting to process shared content")
        let inputItems = extensionContext.inputItems
        print("📦 [BidirectionalShareExt] Total input items: \(inputItems.count)")
        
        // Log detailed information about what iOS is sending
        for (itemIndex, inputItem) in inputItems.enumerated() {
            guard let item = inputItem as? NSExtensionItem else { 
                print("⚠️ [BidirectionalShareExt] Item \(itemIndex) is not NSExtensionItem")
                continue 
            }
            
            print("📝 [BidirectionalShareExt] Input Item \(itemIndex):")
            print("   - Title: \(item.attributedTitle?.string ?? "nil")")
            print("   - Content: \(item.attributedContentText?.string ?? "nil")")
            print("   - Attachments count: \(item.attachments?.count ?? 0)")
            
            if let attachments = item.attachments {
                for (attachmentIndex, attachment) in attachments.enumerated() {
                    print("📎 [BidirectionalShareExt] Attachment \(attachmentIndex):")
                    print("     Registered types: \(attachment.registeredTypeIdentifiers)")
                }
            }
        }
        
        let attachments = extensionContext.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        
        print("🔄 [BidirectionalShareExt] Flattened attachments count: \(attachments.count)")
        
        if attachments.isEmpty {
            print("❌ [BidirectionalShareExt] No attachments to process")
            closeShareExtension()
            return
        }
        
        var shareData: [String: Any] = [:]
        var allFilePaths: [String] = []  // 🔥 KEY FIX: Use array to collect ALL files
        var allTextContent: [String] = []
        let group = DispatchGroup()
        
        for (attachmentIndex, attachment) in attachments.enumerated() {
            print("🔄 [BidirectionalShareExt] Processing attachment \(attachmentIndex)")
            group.enter()
            
            // Process files first (prioritize files over text/URLs)
            if attachment.hasItemConformingToTypeIdentifier("public.file-url") {
                print("📁 [BidirectionalShareExt] Processing file URL attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.file-url", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.image") {
                print("🖼️ [BidirectionalShareExt] Processing image attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.image", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.movie") {
                print("🎬 [BidirectionalShareExt] Processing video attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.movie", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.audio") {
                print("🎵 [BidirectionalShareExt] Processing audio attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.audio", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                print("📄 [BidirectionalShareExt] Processing PDF attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.data") {
                print("📎 [BidirectionalShareExt] Processing data attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.data", options: nil) { [weak self] (item, error) in
                    self?.processFileItem(item: item, error: error, index: attachmentIndex, allFilePaths: &allFilePaths)
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                print("📝 [BidirectionalShareExt] Processing text attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] (item, error) in
                    if let error = error {
                        print("❌ [BidirectionalShareExt] Error loading text: \(error)")
                    } else if let text = item as? String {
                        print("✅ [BidirectionalShareExt] Got text: \(text)")
                        allTextContent.append(text)
                    }
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.url") {
                print("🔗 [BidirectionalShareExt] Processing URL attachment \(attachmentIndex)")
                attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (item, error) in
                    if let error = error {
                        print("❌ [BidirectionalShareExt] Error loading URL: \(error)")
                    } else if let url = item as? URL {
                        print("✅ [BidirectionalShareExt] Got URL: \(url.absoluteString)")
                        allTextContent.append(url.absoluteString)
                    }
                    group.leave()
                }
            } else {
                print("❓ [BidirectionalShareExt] Unknown attachment type \(attachmentIndex), trying first registered type")
                let typeIdentifier = attachment.registeredTypeIdentifiers.first ?? "public.data"
                attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] (item, error) in
                    // Try to process as file first, then as text
                    if let url = item as? URL {
                        print("✅ [BidirectionalShareExt] Got generic file URL: \(url.path)")
                        allFilePaths.append(url.path)
                    } else if let text = item as? String {
                        print("✅ [BidirectionalShareExt] Got generic text: \(text)")
                        allTextContent.append(text)
                    } else {
                        print("⚠️ [BidirectionalShareExt] Generic item is neither URL nor String: \(type(of: item))")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            print("🎯 [BidirectionalShareExt] Processing complete!")
            print("   📁 File paths found: \(allFilePaths.count)")
            for (index, path) in allFilePaths.enumerated() {
                print("      \(index + 1). \(path)")
            }
            print("   📝 Text content found: \(allTextContent.count)")
            for (index, text) in allTextContent.enumerated() {
                print("      \(index + 1). \(text.prefix(100))...")
            }
            
            // Prepare share data
            if !allFilePaths.isEmpty {
                shareData["filePaths"] = allFilePaths  // 🔥 KEY FIX: Use the collected array
                shareData["mimeType"] = self?.determineMimeType(from: allFilePaths.first ?? "") ?? "application/octet-stream"
            }
            
            if !allTextContent.isEmpty {
                shareData["text"] = allTextContent.joined(separator: "\n")
                if shareData["mimeType"] == nil {
                    shareData["mimeType"] = "text/plain"
                }
            }
            
            print("📋 [BidirectionalShareExt] Final share data: \(shareData)")
            self?.saveShareData(shareData)
            self?.navigateToMainApp()
        }
    }
    
    private func processFileItem(item: Any?, error: Error?, index: Int, allFilePaths: inout [String]) {
        if let error = error {
            print("❌ [BidirectionalShareExt] Error loading file \(index): \(error)")
        } else if let url = item as? URL {
            print("✅ [BidirectionalShareExt] Got file URL \(index): \(url.path)")
            allFilePaths.append(url.path)  // 🔥 KEY FIX: APPEND instead of overwrite
        } else {
            print("⚠️ [BidirectionalShareExt] File item \(index) is not URL: \(type(of: item))")
        }
    }
    
    private func determineMimeType(from path: String) -> String {
        let fileExtension = path.lowercased().split(separator: ".").last?.description ?? ""
        
        switch fileExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "bmp":
            return "image/bmp"
        case "heic", "heif":
            return "image/heic"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "avi":
            return "video/x-msvideo"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "zip":
            return "application/zip"
        case "txt":
            return "text/plain"
        case "html":
            return "text/html"
        case "json":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
    
    private func saveShareData(_ data: [String: Any]) {
        guard let appGroupId = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String else {
            print("ShareExtension: AppGroupId not found in Info.plist")
            return
        }
        
        // Save to system temp file for iOS Simulator compatibility (same path as plugin)
        let sharedTmpPath = URL(fileURLWithPath: "/tmp/")
        let shareFilePath = sharedTmpPath.appendingPathComponent("share_intent_data_\(appGroupId).json")
        print("ShareExtension: Using shared system tmp: \(shareFilePath.path)")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            try jsonData.write(to: shareFilePath)
            print("ShareExtension: ✅ Data saved successfully to temp file: \(shareFilePath.path)")
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("ShareExtension: Saved data: \(jsonString)")
            }
        } catch {
            print("ShareExtension: ❌ Error saving to temp file: \(error)")
        }
        
        // Try UserDefaults with App Groups, fall back to standard UserDefaults
        var userDefaults: UserDefaults?
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            userDefaults = groupDefaults
            print("ShareExtension: Using App Group UserDefaults: \(appGroupId)")
        } else {
            userDefaults = UserDefaults.standard
            print("ShareExtension: Fallback to standard UserDefaults")
        }
        
        if let userDefaults = userDefaults {
            // Clear existing data first to avoid stale data
            userDefaults.removeObject(forKey: "shareData")
            userDefaults.removeObject(forKey: "ShareKey")
            userDefaults.removeObject(forKey: "SharingKeyData") 
            userDefaults.synchronize()
            
            // Save data in multiple formats for compatibility
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    // Primary key used by Flutter plugin
                    userDefaults.set(jsonString, forKey: "shareData")
                    
                    // Additional keys for compatibility
                    userDefaults.set([data], forKey: "ShareKey")
                    userDefaults.set(jsonString, forKey: "SharingKeyData")
                    
                    userDefaults.synchronize()
                    print("ShareExtension: Share data saved successfully with keys: shareData, ShareKey, SharingKeyData")
                    print("ShareExtension: Saved data: \(jsonString)")
                }
            } catch {
                print("ShareExtension: Failed to serialize share data: \(error)")
            }
        }
    }
    
    private func navigateToMainApp() {
        guard let bundleId = Bundle.main.object(forInfoDictionaryKey: "MainAppBundleId") as? String else {
            print("ShareExtension: MainAppBundleId not found in Info.plist")
            closeShareExtension()
            return
        }
        
        let urlScheme = "SharingMedia-\(bundleId)://"
        guard let url = URL(string: urlScheme) else {
            print("ShareExtension: Failed to create URL with scheme: \(urlScheme)")
            closeShareExtension()
            return
        }
        
        // Use the proven working approach from FSIShareViewController
        if #available(iOS 18.0, *) {
            // iOS 18+ approach
            var responder: UIResponder? = self
            while responder != nil {
                if let app = responder as? UIApplication {
                    app.open(url, options: [:], completionHandler: { [weak self] success in
                        print("ShareExtension: App launch \(success ? "successful" : "failed")")
                        DispatchQueue.main.async {
                            self?.closeShareExtension()
                        }
                    })
                    break
                }
                responder = responder?.next
            }
        } else {
            // iOS 13-17 approach using selector
            var responder: UIResponder? = self
            let selectorOpenURL = sel_registerName("openURL:")
            while responder != nil {
                if responder?.responds(to: selectorOpenURL) == true {
                    _ = responder?.perform(selectorOpenURL, with: url)
                    print("ShareExtension: Attempted to open URL via selector")
                    break
                }
                responder = responder?.next
            }
            closeShareExtension()
        }
    }
    
    private func closeShareExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
