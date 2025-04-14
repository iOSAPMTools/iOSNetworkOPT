import Foundation
import ObjectiveC

/// APM SDK 的主入口点
public class NetworkAPM {

    private static var isStarted = false
    private static let startOnce: () = {
        // 实际的启动逻辑，只会执行一次
        // Apply default configuration initially or wait for explicit configuration
        // We apply default here, and let start(configuration:) override if provided
        APMDataManager.shared.configure(with: .default)

        URLProtocol.registerClass(APMURLProtocol.self)
        URLSessionConfiguration.swizzleProtocolClasses()
        print("[NetworkAPM] Started and APMURLProtocol registered with default configuration.")
    }()

    /// 启动 APM 监控
    /// 多次调用此方法是安全的，但实际初始化只会执行一次。
    /// - Parameter configuration: Optional configuration for the data manager.
    ///                          If nil, the default configuration is used.
    ///                          If provided, it overrides the default or any previous configuration.
    public static func start(configuration: APMDataManagerConfiguration? = nil) {
        // 使用 dispatch_once 模式确保初始化只执行一次
        _ = startOnce

        // If a specific configuration is provided, apply it.
        // This will override the default applied in startOnce.
        if let config = configuration {
            print("[NetworkAPM] Applying provided configuration.")
            APMDataManager.shared.configure(with: config)
        } else {
            print("[NetworkAPM] Using default configuration (already applied).")
            // Ensure timer starts even if no specific config is passed after init
            // (configure with default in startOnce should have already started it)
        }
    }

    /// 停止 APM 监控 (如果需要的话)
    /// 注意：一旦 Swizzling 完成，完全"停止"可能比较复杂，
    /// 这里仅取消注册 Protocol，但 Swizzling 的效果仍然存在。
    /// 通常 APM 启动后不会停止。
    public static func stop() {
        if isStarted {
            URLProtocol.unregisterClass(APMURLProtocol.self)
            // TODO: Potentially un-swizzle methods if truly needed, but risky.
            isStarted = false
            print("[NetworkAPM] Stopped (APMURLProtocol unregistered). Swizzling remains.")
        }
    }
}

// MARK: - Swizzling for URLSessionConfiguration

extension URLSessionConfiguration {

    // Dictionary to store original method implementations
    private static var originalImplementations = [Selector: IMP]()

    private static let swizzleOnce: () = {
        // Swizzle default session configuration
        swizzle(selector: #selector(getter: URLSessionConfiguration.protocolClasses), for: URLSessionConfiguration.self)

        // Swizzle ephemeral session configuration - they use the same class method implementation
        // We need to get the class method for `default` and `ephemeral`
        // Swizzling the instance method `protocolClasses` on the class object itself should affect both.
        // Let's confirm if `default` and `ephemeral` return instances of the same class or subclasses.
        // They return instances of URLSessionConfiguration, so swizzling the instance method should work.

        // Alternative: Swizzle the class methods `default` and `ephemeral` themselves
        // to return a configuration instance that *already* has the protocolClasses swizzled.
        // Let's stick to swizzling the `protocolClasses` getter directly for now.
    }()

    static func swizzleProtocolClasses() {
        _ = swizzleOnce
    }

    private static func swizzle(selector: Selector, for cls: AnyClass) {
        guard let originalMethod = class_getInstanceMethod(cls, selector) else {
            print("[NetworkAPM] Swizzling Error: Could not get instance method for \(selector)")
            return
        }

        let originalImp = method_getImplementation(originalMethod)

        // Store the original implementation
        originalImplementations[selector] = originalImp

        // Get the implementation of our swizzled method
        // Note: The swizzled method must be defined within this extension
        guard let swizzledMethod = class_getInstanceMethod(cls, #selector(swizzled_protocolClasses)) else {
            print("[NetworkAPM] Swizzling Error: Could not get instance method for swizzled_protocolClasses")
            // Restore original implementation before returning?
            originalImplementations.removeValue(forKey: selector)
            return
        }
        let swizzledImp = method_getImplementation(swizzledMethod)

        // Replace the original method's implementation with the swizzled one
        // class_replaceMethod returns the previous implementation, but we already stored it.
        let didAddMethod = class_addMethod(cls, selector, swizzledImp, method_getTypeEncoding(originalMethod))

        if !didAddMethod {
            // If the method already exists, replace it
            _ = class_replaceMethod(cls, selector, swizzledImp, method_getTypeEncoding(originalMethod))
        } else {
            // This case should not happen if we are swizzling an existing method like protocolClasses
            // If it somehow did, the original IMP is now associated with the selector, 
            // and the swizzled IMP is also associated. This might lead to unexpected behaviour.
            // Consider exchanging implementations instead if addMethod fails unexpectedly.
            print("[NetworkAPM] Swizzling Warning: class_addMethod succeeded unexpectedly for existing selector \(selector). Behaviour might be incorrect.")
            // Fallback or alternative: method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        print("[NetworkAPM] Successfully swizzled \(selector)")
    }

    // The new implementation for protocolClasses getter
    @objc dynamic func swizzled_protocolClasses() -> [AnyClass]? {
        let originalSelector = #selector(getter: URLSessionConfiguration.protocolClasses)

        // Retrieve the original implementation
        guard let originalImp = URLSessionConfiguration.originalImplementations[originalSelector] else {
            print("[NetworkAPM] Error: Could not find original implementation for \(originalSelector)")
            // Attempt to call super? Or return default? Returning nil might be safest if IMP is lost.
            return nil
        }

        // Define the type of the original function
        typealias OriginalGetter = @convention(c) (AnyObject, Selector) -> [AnyClass]?

        // Cast the IMP to the function type
        let originalGetter = unsafeBitCast(originalImp, to: OriginalGetter.self)

        // Call the original implementation using the stored IMP
        // IMPORTANT: Pass `self` as the instance, and the original selector
        var originalProtocols = originalGetter(self, originalSelector)

        // Add our APM protocol
        let apmProtocol: AnyClass = APMURLProtocol.self
        if let protocols = originalProtocols {
            // Check if our protocol is already present
            if !protocols.contains(where: { $0 == apmProtocol }) {
                // Insert at the beginning to ensure it's checked first
                originalProtocols?.insert(apmProtocol, at: 0)
            }
        } else {
            // If originalProtocols was nil, create a new array with our protocol
            originalProtocols = [apmProtocol]
        }

        return originalProtocols
    }
} 