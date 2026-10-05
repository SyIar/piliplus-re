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
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
                throw PiliOfflineError.message("下载服务器返回 HTTP \(code)，请重试以刷新地址")
            }
            guard PiliOfflineStorage.size(location) > 0 else { throw PiliOfflineError.message("服务器返回了空文件") }
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
