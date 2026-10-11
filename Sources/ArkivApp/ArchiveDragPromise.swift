import AppKit
import UniformTypeIdentifiers
import ArkivCore

/// The provider retains its otherwise-weak delegate without a delegate/provider cycle.
final class ArchiveDragPromiseProvider: NSFilePromiseProvider {
    private let promiseDelegate: ArchiveDragPromiseDelegate
    init(session: ArchiveDragSession, item: ArchiveDragItem, queue: OperationQueue,
         feedback: @escaping (Result<ArchiveExtractionReport, Error>) -> Void) {
        promiseDelegate = ArchiveDragPromiseDelegate(session: session, item: item, queue: queue, feedback: feedback)
        let candidate = UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        let type = item.isDirectory ? UTType.folder : (candidate.conforms(to: .data) ? candidate : .data)
        super.init()
        fileType = type.identifier
        delegate = promiseDelegate
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

final class ArchiveDragPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let session: ArchiveDragSession
    private let item: ArchiveDragItem
    private let queue: OperationQueue
    private let feedback: (Result<ArchiveExtractionReport, Error>) -> Void
    init(session: ArchiveDragSession, item: ArchiveDragItem, queue: OperationQueue,
         feedback: @escaping (Result<ArchiveExtractionReport, Error>) -> Void) {
        self.session = session; self.item = item; self.queue = queue; self.feedback = feedback
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        item.name
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        // AppKit invokes this on the shared serial queue only after a receiver requests the file.
        let result = Result { try session.write(item: item, to: url) }
        switch result {
        case .success: completionHandler(nil)
        case .failure(let error): completionHandler(error)
        }
        DispatchQueue.main.async { [feedback] in feedback(result) }
    }
}
