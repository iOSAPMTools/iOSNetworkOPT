import Foundation
import UIKit // For UIApplication
import Network // <-- Import Network framework

// MARK: - APM Configuration

/// Configuration settings for the APM Data Manager
public struct APMDataManagerConfiguration {
   /// The URL endpoint for uploading APM data.
   public let uploadURL: URL
   /// The maximum number of trace records to buffer before triggering an upload.
   public let maxBufferSize: Int
   /// The interval (in seconds) for periodically uploading buffered data.
   public let uploadInterval: TimeInterval

   /// Default configuration
   public static let `default` = APMDataManagerConfiguration(
       uploadURL: URL(string: "https://your-apm-backend.com/apm/network/upload")!, // 请替换为您的实际地址
       maxBufferSize: 50,
       uploadInterval: 60.0
   )

   public init(uploadURL: URL, maxBufferSize: Int, uploadInterval: TimeInterval) {
       self.uploadURL = uploadURL
       self.maxBufferSize = maxBufferSize
       self.uploadInterval = uploadInterval
   }
}

/// 负责管理和上报 APM 数据的单例类
class APMDataManager {

    /// 单例实例
    static let shared = APMDataManager()

    /// 存储 NetworkTraceInfo 对象的缓冲区
    private var buffer: [NetworkTraceInfo] = []

    /// 用于保证缓冲区访问和网络监控回调线程安全的串行队列
    private let queue = DispatchQueue(label: "com.networkapm.datamanager.queue")

    /// 定时器，用于触发定时上报
    private var uploadTimer: Timer?

    /// 标识上报请求的特定 Header Key，避免拦截自身
    static let uploadHeaderKey = "X-APM-Upload-Request"

    /// 当前配置
    private var currentConfiguration: APMDataManagerConfiguration = .default

    // MARK: - Network Monitoring Properties
    /// 网络路径监视器
    private var pathMonitor: NWPathMonitor?
    /// 当前网络类型描述符
    private var currentNetworkType: String = "Unknown"

    /// 私有化构造函数，确保单例
    private init() {
        // 启动网络监控
        startNetworkMonitoring()
        // 定时器将在首次配置或默认配置应用后启动
        // 监听 App 生命周期事件
        setupAppLifecycleObservers()
        print("[APMDataManager] Initialized. Waiting for configuration to start timer.")
    }

    /// 应用新的配置
    /// - Parameter configuration: 新的配置对象
    public func configure(with configuration: APMDataManagerConfiguration) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.currentConfiguration = configuration
            print("[APMDataManager] Configuration updated. URL: \(configuration.uploadURL), BufferSize: \(configuration.maxBufferSize), Interval: \(configuration.uploadInterval)")

            // 配置更新后，重新设置或启动定时器
            // (在主线程执行 Timer 相关操作)
            DispatchQueue.main.async {
                self.setupUploadTimer()
            }
        }
    }

    /// 将收集到的追踪信息添加到缓冲区
    /// - Parameter trace: 网络追踪信息
    func addTrace(_ trace: NetworkTraceInfo) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.buffer.append(trace)
            print("[APMDataManager] Trace added to buffer. Current size: \(self.buffer.count)")

            if self.buffer.count >= self.currentConfiguration.maxBufferSize {
                print("[APMDataManager] Buffer full. Triggering upload.")
                self.flushBufferInternal()
            }
        }
    }

    /// 判断一个请求是否是 APM 的上报请求
    /// - Parameter request: URLRequest
    /// - Returns: Bool
    func isUploadRequest(_ request: URLRequest) -> Bool {
        return request.value(forHTTPHeaderField: APMDataManager.uploadHeaderKey) == "true"
        // return request.url == self.uploadURL // 或者检查 URL
    }

    /// 获取当前的网络路径类型描述符 (线程安全)
    public var currentNetworkPathType: String {
        // 同步读取，确保从 queue 中获取最新值
        queue.sync { currentNetworkType }
    }

    // MARK: - Network Monitoring Setup
    /// 启动网络状态监控
    private func startNetworkMonitoring() {
        // 确保只初始化一次
        guard pathMonitor == nil else { return }

        pathMonitor = NWPathMonitor()
        guard let monitor = pathMonitor else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            // 由于这个闭包可能在任意线程被调用，我们需要 dispatch 到我们的队列来安全地更新属性
            // **修正：将 monitor.start 的 queue 参数设为 self.queue，回调就直接在目标队列执行了**
            // DispatchQueue.main.async { // <-- 错误示范，应该在 self.queue 更新
             guard let self = self else { return }

             var newType = "Unknown"
             if path.status == .satisfied {
                 if path.usesInterfaceType(.wifi) {
                     newType = "WiFi"
                 } else if path.usesInterfaceType(.cellular) {
                     newType = "Cellular"
                 } else if path.usesInterfaceType(.wiredEthernet) {
                     newType = "WiredEthernet"
                 } else {
                     newType = "Other" // 其他满足条件的接口类型
                 }
             } else {
                 // status 不为 satisfied (例如 .requiresConnection, .unsatisfied)
                 newType = "NoConnection"
             }

             // 只有当类型变化时才更新和打印日志
             if newType != self.currentNetworkType {
                 self.currentNetworkType = newType
                 print("[APMDataManager] Network type changed to: \(self.currentNetworkType)")
             }
            // } // 结束 DispatchQueue.main.async
        }

        // 将监控启动到我们的私有队列上，以确保 pathUpdateHandler 在该队列执行，从而保证 currentNetworkType 的线程安全更新
        monitor.start(queue: queue)
        print("[APMDataManager] Network monitoring started.")
    }


    // MARK: - 上报逻辑

    /// 将缓冲区数据上报至服务器 (内部调用，已在 queue 中)
    private func flushBufferInternal(backgroundTaskID: UIBackgroundTaskIdentifier? = nil) {
        // DispatchQueue.assertSpecificQueue(self.queue) // 可选断言

        guard !self.buffer.isEmpty else {
            print("[APMDataManager] Buffer is empty, nothing to flush.")
            return
        }

        let tracesToUpload = self.buffer
        self.buffer.removeAll() // 先清空

        print("[APMDataManager] Flushing \(tracesToUpload.count) traces.")
        uploadTraces(tracesToUpload, backgroundTaskID: backgroundTaskID) { success in
            if !success {
                print("[APMDataManager] Upload failed. Re-adding traces to buffer.")
                // 上报失败，将数据重新放回缓冲区头部
                self.queue.async { // 确保在正确的队列添加
                    self.buffer.insert(contentsOf: tracesToUpload, at: 0)
                }
            } else {
                 print("[APMDataManager] Upload successful.")
            }
        }
    }

    /// 触发缓冲区刷新 (可从外部调用，例如定时器或后台事件)
    func flushBuffer() {
        queue.async { [weak self] in
            self?.flushBufferInternal()
        }
    }

    /// 设置定时器，用于周期性上报
    private func setupUploadTimer() {
        DispatchQueue.main.async {
            guard Thread.isMainThread else {
                print("[APMDataManager] Error: setupUploadTimer called from non-main thread.")
                // 可以选择 dispatch回主线程，或者直接返回
                return
            }

            self.uploadTimer?.invalidate()
            self.uploadTimer = Timer.scheduledTimer(withTimeInterval: self.currentConfiguration.uploadInterval,
                                                  repeats: true)
            { [weak self] _ in
                print("[APMDataManager] Upload timer fired.")
                self?.flushBuffer()
            }
             RunLoop.current.add(self.uploadTimer!, forMode: .common)
        }
    }

    /// 设置监听 App 生命周期事件
    private func setupAppLifecycleObservers() {
        DispatchQueue.main.async {
             NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
             NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.appWillTerminate),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        }
    }

    @objc private func appDidEnterBackground() {
        print("[APMDataManager] App entered background. Triggering upload.")
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        // Start background task
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "APMDataUpload") { [weak self] in
            // Expiration handler: Called if the task takes too long
            print("[APMDataManager] Background task expired or system forced termination.")
            // Attempt to end the task if it hasn't finished uploading
            self?.queue.async {
                // Check if we still need to end the task explicitly
                if backgroundTaskID != .invalid {
                     print("[APMDataManager] Ending background task due to expiration.")
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
        }

        // Dispatch the upload logic to our serial queue
        queue.async { [weak self] in
            guard let self = self else {
                 if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
                return
            }

            // Ensure the task ID is valid before proceeding
            guard backgroundTaskID != .invalid else {
                print("[APMDataManager] Background task ID became invalid before flush could start.")
                return
            }

            print("[APMDataManager] Starting flushBufferInternal in background task.")
            // Pass the backgroundTaskID to flushBufferInternal or its downstream calls (uploadTraces)
            // so it can be ended in the completion handler.
            self.flushBufferInternal(backgroundTaskID: backgroundTaskID) // Modify flushBufferInternal to accept task ID
            // IMPORTANT: flushBufferInternal MUST now call endBackgroundTask on completion.
            // The endBackgroundTask call is *REMOVED* from here.
        }
    }

     @objc private func appWillTerminate() {
        print("[APMDataManager] App will terminate. Triggering final upload.")
        // 尝试同步执行一次 flush
        queue.sync {
             self.flushBufferInternal()
        }
    }

    // MARK: - 上传实现 (占位)
    /// 执行实际的网络上报
    private func uploadTraces(_ traces: [NetworkTraceInfo],
                              backgroundTaskID: UIBackgroundTaskIdentifier? = nil,
                              completion: @escaping (Bool) -> Void) {
       // 使用配置中的 URL
       let url = self.currentConfiguration.uploadURL
       guard !traces.isEmpty else {
           completion(true)
           // End background task if it exists and we are completing early
           if let taskID = backgroundTaskID, taskID != .invalid {
               print("[APMDataManager] Ending background task early (no traces or URL).")
               UIApplication.shared.endBackgroundTask(taskID)
           }
           return
       }
       let encoder = JSONEncoder()
       guard let jsonData = try? encoder.encode(traces) else {
           print("[APMDataManager] Failed to encode traces.")
           completion(false)
           return
       }
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       request.setValue("true", forHTTPHeaderField: APMDataManager.uploadHeaderKey)
       request.httpBody = jsonData
       print("[APMDataManager] Sending \(traces.count) traces to \(url.absoluteString)")
       let config = URLSessionConfiguration.ephemeral
       // Important: Ensure APM protocol is NOT used for upload requests
       // config.protocolClasses = config.protocolClasses?.filter { $0 != APMURLProtocol.self }
       // A better approach is to create a session configuration specifically without our protocol
       // Or rely on the header check in APMURLProtocol's canInit(with:)
       let uploadSession = URLSession(configuration: config)
       let task = uploadSession.dataTask(with: request) { data, response, error in
           // ... (处理响应和调用 completion) ...
            if let error = error {
               print("[APMDataManager] Upload error: \(error.localizedDescription)")
               completion(false)
               return
           } else if let httpResponse = response as? HTTPURLResponse {
               if (200..<300).contains(httpResponse.statusCode) {
                   print("[APMDataManager] Upload successful (Status Code: \(httpResponse.statusCode))")
                   completion(true)
               } else {
                   print("[APMDataManager] Upload failed (Status Code: \(httpResponse.statusCode))")
                   completion(false)
               }
           } else {
               print("[APMDataManager] Upload failed: Invalid response")
               completion(false)
           }

           // End the background task regardless of success or failure
           if let taskID = backgroundTaskID, taskID != .invalid {
               print("[APMDataManager] Ending background task in upload completion.")
               UIApplication.shared.endBackgroundTask(taskID)
           }
       }
       task.resume()
    }


    deinit {
        pathMonitor?.cancel() // <-- 停止网络监控
        uploadTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}