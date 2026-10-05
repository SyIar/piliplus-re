import Foundation
import PiliPlaybackCore

nonisolated final class PiliOfflineSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let identity = OfflineTaskIdentity(taskDescription: downloadTask.taskDescription) else { return }
        DispatchQueue.main.async {
            PiliOfflineStore.shared.receivedProgress(identity, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let identity = OfflineTaskIdentity(taskDescription: downloadTask.taskDescription) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else {
                throw OfflineDownloadValidation.Failure.response(0)
            }
            try OfflineDownloadValidation.validate(
                status: response.statusCode, mimeType: response.mimeType,
                contentLength: response.expectedContentLength,
                contentRange: response.value(forHTTPHeaderField: "Content-Range"),
                contentEncoding: response.value(forHTTPHeaderField: "Content-Encoding"),
                fileSize: PiliOfflineStorage.size(location)
            )
            // Move synchronously: URLSession removes its temporary file after this callback returns.
            let staging = try PiliOfflineStorage.staging(identity)
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.moveItem(at: location, to: staging)
            DispatchQueue.main.async { PiliOfflineStore.shared.receivedFile(identity, staging: staging) }
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { PiliOfflineStore.shared.receivedFailure(identity, message: message, resumeData: nil) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let identity = OfflineTaskIdentity(taskDescription: task.taskDescription) else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let message = error.localizedDescription
        DispatchQueue.main.async { PiliOfflineStore.shared.receivedFailure(identity, message: message, resumeData: resumeData) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { PiliOfflineStore.shared.finishedBackgroundEvents() }
    }
}
