import Foundation

/// 存储单次网络请求的完整追踪信息
public struct NetworkTraceInfo: Codable {
    /// 请求的唯一标识
    public let traceID: String
    /// 请求 URL
    public let url: String
    /// HTTP 方法
    public let method: String
    /// 请求头 (简化为字典，实际可能需要更复杂处理)
    public let requestHeaders: [String: String]?
    /// 响应头 (简化为字典)
    public let responseHeaders: [String: String]?
    /// HTTP 状态码
    public let statusCode: Int?
    /// 错误信息描述
    public let errorDescription: String?
    /// Error code if an error occurred
    public let errorCode: Int?
    /// Error domain if an error occurred
    public let errorDomain: String?
    /// 各阶段耗时信息
    public let timing: Timing
    /// 上行流量 (Bytes)
    public let sentBytes: Int64?
    /// 下行流量 (Bytes)
    public let receivedBytes: Int64?
    /// 网络类型 (例如 "WiFi", "Cellular")
    public let networkType: String?
    /// 请求开始时间戳 (Unix timestamp, milliseconds)
    public let startTime: TimeInterval
    /// 请求结束时间戳 (Unix timestamp, milliseconds)
    public let endTime: TimeInterval
    /// 请求总耗时 (milliseconds)
    public let totalTime: TimeInterval

    /// 初始化方法
    public init(traceID: String = UUID().uuidString,
                url: String,
                method: String,
                requestHeaders: [String: String]? = nil,
                responseHeaders: [String: String]? = nil,
                statusCode: Int? = nil,
                errorDescription: String? = nil,
                errorCode: Int? = nil,
                errorDomain: String? = nil,
                timing: Timing,
                sentBytes: Int64? = nil,
                receivedBytes: Int64? = nil,
                networkType: String? = nil,
                startTime: TimeInterval,
                endTime: TimeInterval) {
        self.traceID = traceID
        self.url = url
        self.method = method
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.statusCode = statusCode
        self.errorDescription = errorDescription
        self.errorCode = errorCode
        self.errorDomain = errorDomain
        self.timing = timing
        self.sentBytes = sentBytes
        self.receivedBytes = receivedBytes
        self.networkType = networkType
        self.startTime = startTime
        self.endTime = endTime
        self.totalTime = (endTime - startTime) * 1000 // 转换为毫秒
    }

    /// 存储各阶段耗时信息 (单位: 毫秒)
    public struct Timing: Codable {
        /// DNS 解析耗时
        public var dnsLookupTime: TimeInterval?
        /// TCP 连接耗时 (包含 TLS 握手)
        public var tcpConnectTime: TimeInterval?
        /// TLS 安全连接耗时 (如果启用 HTTPS)
        public var tlsConnectTime: TimeInterval?
        /// 请求发送耗时
        public var requestSendTime: TimeInterval?
        /// 等待服务器首包响应耗时
        public var waitingForResponseTime: TimeInterval?
        /// 响应数据接收耗时
        public var responseReceiveTime: TimeInterval?

        /// 初始化方法
        public init(dnsLookupTime: TimeInterval? = nil,
                    tcpConnectTime: TimeInterval? = nil,
                    tlsConnectTime: TimeInterval? = nil,
                    requestSendTime: TimeInterval? = nil,
                    waitingForResponseTime: TimeInterval? = nil,
                    responseReceiveTime: TimeInterval? = nil) {
            self.dnsLookupTime = dnsLookupTime
            self.tcpConnectTime = tcpConnectTime
            self.tlsConnectTime = tlsConnectTime
            self.requestSendTime = requestSendTime
            self.waitingForResponseTime = waitingForResponseTime
            self.responseReceiveTime = responseReceiveTime
        }
    }
} 