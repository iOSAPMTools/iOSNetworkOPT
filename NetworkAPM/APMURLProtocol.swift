import Foundation
import UIKit // For Network type detection (if needed via other means)

class APMURLProtocol: URLProtocol, URLSessionDataDelegate, URLSessionTaskDelegate {

    // MARK: - Properties

    /// The session used to make the actual network request.
    /// Lazily initialized to ensure the configuration doesn't include this protocol.
    private lazy var session: URLSession = {
        // Create a configuration that *doesn't* include this protocol class
        // to avoid an infinite loop. We copy the default configuration
        // and remove our protocol if present (though swizzling might make this tricky).
        // A safer approach is often to use .ephemeral or a custom config known
        // not to be swizzled further, or rely on the header check in canInit.
        let config = URLSessionConfiguration.ephemeral // Use ephemeral to avoid caching issues and interference
        // config.protocolClasses = config.protocolClasses?.filter { $0 != APMURLProtocol.self } // Attempt to remove, might be ineffective due to swizzling point
        return URLSession(configuration: config, delegate: self, delegateQueue: nil) // Process delegate methods on a background queue
    }()

    /// The data task performing the network request.
    private var dataTask: URLSessionDataTask?
    /// Stores the received response.
    private var currentResponse: URLResponse?
    /// Stores the received data.
    private var receivedData: NSMutableData?
    /// Timestamp when the request started loading.
    private var startTime: TimeInterval?
    /// Stores the detailed timing information.
    private var timingInfo = NetworkTraceInfo.Timing()

    // MARK: - URLProtocol Overrides

    /// Determines if this protocol can handle the given request.
    override class func canInit(with request: URLRequest) -> Bool {
        // 1. Check if it's an APM upload request - if so, ignore it.
        if APMDataManager.shared.isUploadRequest(request) {
             // print("[APMURLProtocol] Ignoring APM upload request: \(request.url?.absoluteString ?? "N/A")")
            return false
        }

        // 2. Check for supported schemes (http and https).
        guard let scheme = request.url?.scheme else { return false }
        let supportedSchemes = ["http", "https"]
        if !supportedSchemes.contains(scheme.lowercased()) {
             // print("[APMURLProtocol] Ignoring non-http(s) request: \(request.url?.absoluteString ?? "N/A")")
            return false
        }

        // 3. Avoid handling requests already marked by this protocol (less common, but for safety).
        if URLProtocol.property(forKey: "APMURLProtocolHandled", in: request) != nil {
             // print("[APMURLProtocol] Ignoring already handled request: \(request.url?.absoluteString ?? "N/A")")
            return false
        }

         // print("[APMURLProtocol] Handling request: \(request.url?.absoluteString ?? "N/A")")
        return true
    }

    /// Returns the canonical version of the request. Required, but often no changes needed.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    /// Starts loading the request.
    override func startLoading() {
        // Mark the request as handled to potentially prevent loops (though canInit should be primary guard).
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            // Should not happen with standard requests
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: [NSLocalizedDescriptionKey: "Invalid request object"]))
            return
        }
        URLProtocol.setProperty(true, forKey: "APMURLProtocolHandled", in: mutableRequest)

        self.startTime = Date().timeIntervalSince1970
        self.receivedData = NSMutableData()
        self.dataTask = session.dataTask(with: mutableRequest as URLRequest)
        self.dataTask?.resume()
        print("[APMURLProtocol] Started loading: \(request.url?.absoluteString ?? "N/A")")
    }

    /// Stops loading the request.
    override func stopLoading() {
        print("[APMURLProtocol] Stop loading: \(request.url?.absoluteString ?? "N/A")")
        self.dataTask?.cancel()
        self.dataTask = nil
        // Invalidate the session to release resources and break delegate retain cycles.
        self.session.invalidateAndCancel()
    }

    // MARK: - URLSessionDataDelegate

    /// Called when the initial response is received.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("[APMURLProtocol] Received response: \(response.url?.absoluteString ?? "N/A") Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        self.currentResponse = response
        self.receivedData?.length = 0 // Reset data for this response
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed) // Notify client
        completionHandler(.allow) // Allow processing to continue
    }

    /// Called when data is received.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.receivedData?.append(data)
        self.client?.urlProtocol(self, didLoad: data) // Notify client
    }

    // MARK: - URLSessionTaskDelegate

    /// Called when metrics are collected for the task.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        print("[APMURLProtocol] Finished collecting metrics for: \(task.originalRequest?.url?.absoluteString ?? "N/A")")

        guard let metric = metrics.transactionMetrics.last else {
            // No transaction metrics available
            return
        }

        // Helper to calculate duration, returning nil if start/end is distantPast or zero
        func calculateDuration(start: Date?, end: Date?) -> TimeInterval? {
            guard let s = start, let e = end, s > .distantPast, e > .distantPast, e >= s else { return nil }
            return (e.timeIntervalSince(s) * 1000).rounded() // Convert to milliseconds and round
        }

        timingInfo.dnsLookupTime = calculateDuration(start: metric.domainLookupStartDate, end: metric.domainLookupEndDate)

        let tcpConnectDuration = calculateDuration(start: metric.connectStartDate, end: metric.connectEndDate)
        timingInfo.tlsConnectTime = calculateDuration(start: metric.secureConnectionStartDate, end: metric.secureConnectionEndDate)

        if let tlsTime = timingInfo.tlsConnectTime, let tcpTime = tcpConnectDuration {
            // Subtract TLS time from the overall connect time to get pure TCP time
             timingInfo.tcpConnectTime = max(0, tcpTime - tlsTime) // Ensure non-negative
        } else {
            // If no TLS, TCP time is the full connect duration
            timingInfo.tcpConnectTime = tcpConnectDuration
        }

        timingInfo.requestSendTime = calculateDuration(start: metric.requestStartDate, end: metric.requestEndDate)
        // Waiting time is from end of request send to start of response receive
        timingInfo.waitingForResponseTime = calculateDuration(start: metric.requestEndDate, end: metric.responseStartDate)
        timingInfo.responseReceiveTime = calculateDuration(start: metric.responseStartDate, end: metric.responseEndDate)

         print("[APMURLProtocol] Timing - DNS: \(timingInfo.dnsLookupTime ?? -1)ms, TCP: \(timingInfo.tcpConnectTime ?? -1)ms, TLS: \(timingInfo.tlsConnectTime ?? -1)ms, ReqSend: \(timingInfo.requestSendTime ?? -1)ms, Wait: \(timingInfo.waitingForResponseTime ?? -1)ms, RespRecv: \(timingInfo.responseReceiveTime ?? -1)ms")
    }


    /// Called when the task completes (either successfully or with an error).
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let endTime = Date().timeIntervalSince1970
        print("[APMURLProtocol] Did complete (\(task.originalRequest?.url?.absoluteString ?? "N/A")) with error: \(error?.localizedDescription ?? "nil")")

        // --- Notify client first ---
        if let completionError = error {
             // Don't forward cancellation errors if stopLoading was called
             if (completionError as NSError).code != NSURLErrorCancelled {
                 print("[APMURLProtocol] Forwarding error to client: \(completionError.localizedDescription)")
                self.client?.urlProtocol(self, didFailWithError: completionError)
            } else {
                 print("[APMURLProtocol] Task cancelled, not forwarding error.")
            }
        } else {
             print("[APMURLProtocol] Forwarding finish loading to client.")
            self.client?.urlProtocolDidFinishLoading(self)
        }

        // --- Then, extract data and build NetworkTraceInfo ---
        guard let reqStartTime = self.startTime, let requestUrl = task.originalRequest?.url?.absoluteString else {
            print("[APMURLProtocol] Missing start time or URL, cannot record trace.")
            // Session cleanup happens in finally/defer block equivalent
            return
        }

        // Get current network type (ensure APMDataManager is initialized)
        let networkType = APMDataManager.shared.currentNetworkPathType

        let httpResponse = self.currentResponse as? HTTPURLResponse
        let requestHeaders = task.originalRequest?.allHTTPHeaderFields
        let responseHeaders = httpResponse?.allHeaderFields as? [String: String] // Cast to dictionary
        let statusCode = httpResponse?.statusCode

        // Use task counts directly
        let sentBytes = task.countOfBytesSent > 0 ? task.countOfBytesSent : nil
        let receivedBytes = task.countOfBytesReceived > 0 ? task.countOfBytesReceived : nil

        // Extract error code and domain if error exists
        let nsError = error as NSError?
        let errorCode = nsError?.code
        let errorDomain = nsError?.domain

        // Create NetworkTraceInfo instance using collected data
        let traceInfo = NetworkTraceInfo(
            url: requestUrl,
            method: task.originalRequest?.httpMethod ?? "UNKNOWN",
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            statusCode: statusCode,
            errorDescription: error?.localizedDescription, // Use original error description
            errorCode: errorCode, // Use extracted code
            errorDomain: errorDomain, // Use extracted domain
            timing: self.timingInfo, // Use timing info populated by didFinishCollecting
            sentBytes: sentBytes,
            receivedBytes: receivedBytes,
            networkType: networkType, // Use detected network type
            startTime: reqStartTime,
            endTime: endTime
        )

        // Pass traceInfo to APMDataManager
        APMDataManager.shared.addTrace(traceInfo)
        print("[APMURLProtocol] Trace info added to manager for \(requestUrl)")

        // Note: Session cleanup (`session.invalidateAndCancel()`) is usually done in `stopLoading`
        // or implicitly when the delegate is deallocated if using ephemeral sessions.
        // Explicitly calling it here might be redundant if stopLoading is always called,
        // but can act as a safeguard. However, calling invalidateAndCancel also prevents
        // further delegate calls, so ensure it's the last step related to this task/session.
        // Given we create a session per request essentially, invalidating is reasonable.
        // self.session.finishTasksAndInvalidate() // Alternative: let ongoing tasks finish
    }
}