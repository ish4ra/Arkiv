import CryptoKit
import Foundation

/// One bounded HTTPS download, streamed to a file and hashed as it arrives.
///
/// * The response must be HTTP 200; redirects are followed only to allowed HTTPS hosts.
/// * More bytes than `maximum` (or than a known `expectedSize`) stop the transfer at once.
/// * The result must have exactly `expectedSize` bytes and the expected SHA-256, when given.
/// * Cancellation (the Swift task, or `cancel()`) stops the transfer; the partial
///   file is left for the caller's staging cleanup and is never used.
final class ThemeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result { let file: URL; let size: Int; let sha256: String }

    private let request: URLRequest
    private let destination: URL
    private let expectedSize: Int?
    private let maximum: Int
    private let expectedSHA256: String?
    private let hosts: ThemeHostPolicy
    private let progress: @Sendable (Double) -> Void
    private let queue = OperationQueue()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var received = 0
    private var failure: Error?
    private var continuation: CheckedContinuation<Result, Error>?
    private var cancelled = false

    init(url: URL, destination: URL, expectedSize: Int?, maximum: Int, sha256: String?, hosts: ThemeHostPolicy,
         configuration: URLSessionConfiguration, progress: @escaping @Sendable (Double) -> Void = { _ in }) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.setValue("application/octet-stream, application/json", forHTTPHeaderField: "Accept")
        self.request = request; self.destination = destination; self.expectedSize = expectedSize
        self.maximum = expectedSize.map { min($0, maximum) } ?? maximum
        self.expectedSHA256 = sha256; self.hosts = hosts; self.progress = progress
        super.init()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func run() async throws -> Result {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                queue.addOperation { [self] in
                    if cancelled { continuation.resume(throwing: ThemeError.cancelled); session?.invalidateAndCancel(); return }
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]),
                          let handle = try? FileHandle(forWritingTo: destination) else {
                        continuation.resume(throwing: ThemeError.download("the download could not be stored.")); return
                    }
                    self.handle = handle
                    self.continuation = continuation
                    task = session?.dataTask(with: request)
                    task?.resume()
                }
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        queue.addOperation { [self] in
            cancelled = true
            failure = failure ?? ThemeError.cancelled
            task?.cancel()
        }
    }

    private func stop(_ error: Error) {
        if failure == nil { failure = error }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard hosts.allowsRedirect(request.url) else {
            stop(ThemeError.download("it was redirected to an unexpected location."))
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            stop(ThemeError.download("the server answered \(code == 0 ? "unexpectedly" : "HTTP \(code)")."))
            completionHandler(.cancel); return
        }
        if response.expectedContentLength > Int64(maximum) { stop(ThemeError.tooLarge); completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        received += data.count
        guard received <= maximum else { stop(ThemeError.tooLarge); return }
        do { try handle?.write(contentsOf: data) } catch { stop(ThemeError.download("the download could not be stored.")); return }
        hasher.update(data: data)
        if let expectedSize { progress(Double(received) / Double(max(expectedSize, 1))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close(); handle = nil
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let outcome: Swift.Result<Result, Error>
        if let failure { outcome = .failure(failure) }
        else if let error {
            let offline = (error as? URLError).map { [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed].contains($0.code) } ?? false
            outcome = .failure(ThemeError.download(offline ? "Arkiv could not connect. Check your internet connection." : error.localizedDescription))
        } else if let expectedSize, received != expectedSize { outcome = .failure(ThemeError.download("it ended early.")) }
        else if let expectedSHA256, digest != expectedSHA256 { outcome = .failure(ThemeError.checksumMismatch) }
        else { outcome = .success(Result(file: destination, size: received, sha256: digest)) }
        session.finishTasksAndInvalidate()
        self.session = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: outcome)
    }
}
