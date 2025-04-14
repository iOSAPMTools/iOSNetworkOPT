# iOSNetworkOPT (NetworkAPM 库)

一个轻量级的 iOS 网络性能监控 (APM) 库，旨在帮助开发者理解和优化应用的网
络行为。

## 核心功能

*   **自动拦截**: 通过 `URLProtocol` 和 Method Swizzling 自动拦截基于 `URLSession` 
    发起的 HTTP/HTTPS 请求。
*   **指标收集**: 收集详细的网络请求指标，包括：
    *   **基础信息**: URL, HTTP 方法, HTTP 状态码, 请求/响应头。
    *   **耗时分解**: DNS 解析、TCP 连接、TLS 握手、请求发送、等待服务器响应、响
        应接收。
    *   **错误信息**: 详细的错误描述、错误码 (Error Code) 和错误域 (Error Domain)
        。
    *   **流量统计**: 上行和下行流量（Bytes）。
    *   **网络环境**: 自动检测当前网络类型（WiFi, Cellular, 无连接等）。
*   **数据缓冲与上报**: 将收集到的数据缓存在内存中，并根据配置的缓冲区大小或时间
    间隔自动上报到指定的后端服务器。
*   **后台任务支持**: 应用进入后台时，尝试完成最后的数据上报。
*   **配置灵活**: 支持通过代码配置上报地址、缓冲区大小和上报时间间隔。
*   **易于集成**: 提供简单的 API 来启动和配置监控。

## 安装指南

### Swift Package Manager (SPM)

1.  在 Xcode 中，选择 "File" > "Add Packages..."
2.  在搜索栏中输入你的仓库 URL (例如 `https://github.com/your_github_username/iOSNetworkOPT.git` - **请替换为您的实际 URL**)。
3.  选择 `NetworkAPM` 包，设置版本规则（例如 "Up to Next Major"），然后点击 "
    Add Package"。
4.  将 `NetworkAPM` 库添加到你的 App Target 的 "Frameworks, Libraries, and 
    Embedded Content" 部分。

### CocoaPods

1.  确保你的项目根目录中有一个 `Podfile`。
2.  在 `Podfile` 中添加以下行：

    ```ruby
    # 请确保这里的 Git URL 和 tag 指向你的仓库
    pod 'NetworkAPM', :git => 'https://github.com/iOSAPMTools/iOSNetworkOPT.git'
    ```
    (**请替换 URL 和 tag**) 

3.  在终端中，导航到项目根目录并运行 `pod install`。
4.  打开生成的 `.xcworkspace` 文件进行开发。

**注意**: 在使用 CocoaPods 版本前，请确保 `NetworkAPM.podspec` 文件中的 `s.homepage`, `s.license`, `s.author`, 和 `s.source` 字段已更新为您的实际信息，并且仓库中存在对应的 Git Tag (`0.1.0`)。

## 使用方法

在您的 `AppDelegate.swift` (或应用程序启动的早期阶段) 导入并启动 `NetworkAPM`。

```swift
import UIKit
import NetworkAPM // 导入库

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions 
launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // *** 启动 NetworkAPM ***
        // 1. 使用默认配置启动
        // NetworkAPM.start()

        // 2. 或者，使用自定义配置启动
        let customConfig = APMDataManagerConfiguration(
            uploadURL: URL(string: "https://your-actual-apm-backend.com/upload")!, // 替换为你的真实后端地址
            maxBufferSize: 100, // 缓冲区达到 100 条时上报
            uploadInterval: 300.0 // 每 300 秒（5分钟）上报一次
        )
        NetworkAPM.start(configuration: customConfig)
        
        print("NetworkAPM Started.")
        // ***********************

        // 你的其他启动代码...
        return true
    }

    // ... 其他 AppDelegate 方法 ...
}
```

启动后，`NetworkAPM` 会自动开始监控网络请求，并将数据发送到配置的后端地址。

## 收集的数据 (`NetworkTraceInfo`)

每次网络请求完成后，会生成一个 `NetworkTraceInfo` 对象，包含以下信息：

*   `traceID`: (String) 请求的唯一标识。
*   `url`: (String) 请求的完整 URL。
*   `method`: (String) HTTP 请求方法 (GET, POST 等)。
*   `requestHeaders`: ([String: String]?) 请求头信息。
*   `responseHeaders`: ([String: String]?) 响应头信息。
*   `statusCode`: (Int?) HTTP 状态码。
*   `errorDescription`: (String?) 如果发生错误，错误的本地化描述。
*   `errorCode`: (Int?) 如果发生错误，NSError 的错误码。
*   `errorDomain`: (String?) 如果发生错误，NSError 的错误域。
*   `timing`: (Timing) 包含各阶段耗时的结构体：
    *   `dnsLookupTime`: (TimeInterval?) DNS 解析耗时 (毫秒)。
    *   `tcpConnectTime`: (TimeInterval?) TCP 连接建立耗时 (不含 TLS, 毫秒)。
    *   `tlsConnectTime`: (TimeInterval?) TLS 握手耗时 (毫秒)。
    *   `requestSendTime`: (TimeInterval?) 请求数据发送耗时 (毫秒)。
    *   `waitingForResponseTime`: (TimeInterval?) 等待服务器首包响应耗时 (毫秒)。
    *   `responseReceiveTime`: (TimeInterval?) 响应数据接收耗时 (毫秒)。
*   `sentBytes`: (Int64?) 上传的流量大小 (Bytes)。
*   `receivedBytes`: (Int64?) 下载的流量大小 (Bytes)。
*   `networkType`: (String?) 当前网络类型 ("WiFi", "Cellular", "NoConnection", 
    "Unknown" 等)。
*   `startTime`: (TimeInterval) 请求开始的时间戳 (秒，Unix epoch)。
*   `endTime`: (TimeInterval) 请求结束的时间戳 (秒，Unix epoch)。
*   `totalTime`: (TimeInterval) 请求总耗时 (毫秒)。

## 网络优化实践：利用 APM 数据

收集到的 `NetworkTraceInfo` 数据是进行网络优化的宝贵依据。以下是一些利用这些数据进行优化的方向：

1.  **识别慢请求**: 
    *   分析 `totalTime` 较大的请求，找出应用中的慢接口或资源。
    *   结合 `Timing` 数据分析慢的原因：是 DNS 解析慢 (`dnsLookupTime`)？TCP 连接慢 (
        `tcpConnectTime`)？TLS 握手慢 (`tlsConnectTime`)？服务器处理慢 (
        `waitingForResponseTime`)？还是数据传输慢 (`responseReceiveTime`)？
    *   **优化方向**: 
        *   **DNS 慢**: 考虑使用 HTTPDNS，或优化 DNS 预解析。
        *   **TCP/TLS 慢**: 检查服务器配置，考虑连接复用 (HTTP/2, HTTP/3)，或使用更
            快的 TLS 协议版本。
        *   **等待服务器慢**: 这是后端性能问题，需要后端开发人员优化接口处理速度。
        *   **数据传输慢**: 检查响应体大小 (`receivedBytes`)，考虑压缩响应数据（Gzip）
            ，优化图片/资源格式和大小，或者使用分页加载。

2.  **分析网络错误**: 
    *   聚合分析 `statusCode`，找出常见的非 2xx 状态码，了解服务器错误类型。
    *   分析 `errorCode` 和 `errorDomain`，定位客户端网络错误，如 DNS 解析失败 (
        `NSURLErrorDomain`, `NSURLErrorCannotFindHost`)、连接超时 (
        `NSURLErrorDomain`, `NSURLErrorTimedOut`)、SSL/TLS 错误 (
        `NSURLErrorDomain`, `NSURLErrorSecureConnectionFailed`) 等。
    *   **优化方向**: 根据错误类型修复问题，例如改进弱网处理逻辑、检查 SSL 证书配置
        、处理服务器端错误等。

3.  **监控流量消耗**: 
    *   分析 `sentBytes` 和 `receivedBytes`，了解哪些请求消耗了最多的流量。
    *   **优化方向**: 优化请求参数，减少不必要的上行数据；优化响应数据，例如压缩、
        图片优化、增量更新等，减少下行流量。

4.  **区分网络环境**: 
    *   比较不同 `networkType` (WiFi vs Cellular) 下的请求耗时、错误率和流量。
    *   **优化方向**: 针对移动网络环境（Cellular）进行特别优化，例如采用更小的资源
        、增加缓存、提供更友好的弱网提示和重试机制。

5.  **发现异常模式**: 
    *   通过聚合和可视化 APM 数据，发现异常的时间模式（例如特定时间段错误率升高）或
        版本模式（例如新版本发布后性能下降）。

## 配置 (`APMDataManagerConfiguration`)

可以在 `NetworkAPM.start(configuration:)` 时传入一个 `APMDataManagerConfiguration` 
实例来自定义数据管理器的行为：

```swift
public struct APMDataManagerConfiguration {
   /// 上报数据的 URL 端点。
   public let uploadURL: URL
   /// 触发上报的最大缓冲区记录数。
   public let maxBufferSize: Int
   /// 定期上报缓冲数据的时间间隔（秒）。
   public let uploadInterval: TimeInterval

   /// 默认配置
   public static let `default`: APMDataManagerConfiguration

   public init(uploadURL: URL, maxBufferSize: Int, uploadInterval: TimeInterval)
}
```

## 许可证

本项目采用 MIT 许可证。