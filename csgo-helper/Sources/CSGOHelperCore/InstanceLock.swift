import Darwin
import Foundation

/// Защита от второго экземпляра на основе flock(2). Ядро отпускает блокировку
/// даже при падении процесса, поэтому устаревший файл не блокирует будущие запуски.
public final class InstanceLock {
    private var descriptor: Int32 = -1
    private let url: URL

    public init(url: URL = HelperPaths.lockURL) {
        self.url = url
    }

    deinit {
        release()
    }

    public func acquire() throws {
        guard descriptor < 0 else { return }
        try HelperPaths.ensureDirectory(url.deletingLastPathComponent())
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw HelperError.instanceAlreadyRunning("не удалось открыть lock-файл \(url.path)")
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            let pid = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            throw HelperError.instanceAlreadyRunning(
                "helper уже запущен\(pid.isEmpty ? "" : " (pid \(pid.trimmingCharacters(in: .whitespacesAndNewlines)))")"
            )
        }
        self.descriptor = descriptor
        ftruncate(descriptor, 0)
        let text = "\(getpid())\n"
        _ = text.withCString { pointer in
            write(descriptor, pointer, strlen(pointer))
        }
    }

    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
