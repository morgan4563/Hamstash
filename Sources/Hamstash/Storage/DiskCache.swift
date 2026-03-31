// DiskCache.swift
// FileManager 기반 디스크 캐시

import Foundation

/// FileManager 기반 디스크 캐시
///
/// `Library/Caches/` 디렉토리에 Data를 파일로 저장/조회/삭제한다.
/// NSLock으로 스레드 안전을 보장하며, 바이트 기반 용량 제한과 TTL 만료를 지원한다.
///
/// ```swift
/// let disk = DiskCache(config: .init(
///     name: "images",
///     totalCostLimit: .megabytes(50),     // 50MB
///     maxAge: 7 * 24 * 60 * 60           // 7일
/// ))
/// disk.store(imageData, forKey: "profile_123")
/// let data = disk.value(forKey: "profile_123")
/// ```
///
/// **저장 경로**: `Library/Caches/com.hamstash.diskcache/{name}/`
/// **키 해싱**: SHA256으로 파일명 변환 (URL 등 특수문자 안전 처리)
/// **용량 관리**: `totalCostLimit` 초과 시 가장 오래된 파일부터 제거
/// **만료 관리**: `maxAge` 초과 항목은 조회 시 자동 삭제 (Lazy Deletion)
public final class DiskCache: @unchecked Sendable {

    // MARK: - 설정

    /// 바이트 크기를 읽기 쉽게 표현하기 위한 타입
    ///
    /// ```swift
    /// DiskCache.Configuration(totalCostLimit: .megabytes(50))   // 50MB
    /// DiskCache.Configuration(totalCostLimit: .gigabytes(1))    // 1GB
    /// ```
    public struct ByteSize: Sendable, Equatable {
        /// 바이트 단위 값
        public let bytes: Int

        /// 바이트 단위로 직접 지정한다.
        public init(bytes: Int) {
            precondition(bytes >= 0, "bytes는 0 이상이어야 합니다. 현재 값: \(bytes)")
            self.bytes = bytes
        }

        /// 제한 없음 (0바이트)
        public static let unlimited = ByteSize(bytes: 0)

        /// 킬로바이트 단위로 지정한다.
        public static func kilobytes(_ value: Int) -> ByteSize {
            precondition(value > 0, "kilobytes는 0보다 커야 합니다. 현재 값: \(value)")
            return ByteSize(bytes: value * 1024)
        }

        /// 메가바이트 단위로 지정한다.
        public static func megabytes(_ value: Int) -> ByteSize {
            precondition(value > 0, "megabytes는 0보다 커야 합니다. 현재 값: \(value)")
            return ByteSize(bytes: value * 1024 * 1024)
        }

        /// 기가바이트 단위로 지정한다.
        public static func gigabytes(_ value: Int) -> ByteSize {
            precondition(value > 0, "gigabytes는 0보다 커야 합니다. 현재 값: \(value)")
            return ByteSize(bytes: value * 1024 * 1024 * 1024)
        }
    }

    /// 디스크 캐시 설정
    public struct Configuration: Sendable {
        /// 캐시 이름 (디렉토리명으로 사용)
        public let name: String
        /// 최대 용량 (바이트). `.unlimited`이면 무제한
        public let totalCostLimit: Int
        /// 항목 최대 수명 (초). 0이면 무제한
        public let maxAge: TimeInterval

        /// - Parameters:
        ///   - name: 캐시 이름 (기본: "default")
        ///   - totalCostLimit: 최대 용량 (기본: `.unlimited` = 무제한)
        ///   - maxAge: 최대 수명 초 (기본: 0 = 무제한)
        public init(
            name: String = "default",
            totalCostLimit: ByteSize = .unlimited,
            maxAge: TimeInterval = 0
        ) {
            precondition(!name.isEmpty, "캐시 이름은 비어있을 수 없습니다.")
            precondition(maxAge >= 0, "maxAge는 0 이상이어야 합니다. 현재 값: \(maxAge)")

            self.name = name
            self.totalCostLimit = totalCostLimit.bytes
            self.maxAge = maxAge
        }
    }

    // MARK: - 프로퍼티

    private let config: Configuration
    private let directory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    // MARK: - 초기화

    /// - Parameter config: 디스크 캐시 설정
    public init(config: Configuration = .init()) {
        self.config = config

        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.directory = cacheDir
            .appendingPathComponent("com.hamstash.diskcache", isDirectory: true)
            .appendingPathComponent(config.name, isDirectory: true)

        // 디렉토리가 없으면 생성
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 테스트용 — 저장 경로를 직접 지정할 수 있는 초기화
    init(config: Configuration, directory: URL) {
        self.config = config
        self.directory = directory

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - 공개 API

    /// 데이터를 디스크에 저장한다.
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 식별 키
    public func store(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = filePath(forKey: key)
        do {
            try data.write(to: fileURL)
        } catch {
            #if DEBUG
            print("⚠️ [Hamstash] 디스크 캐시 저장 실패 (key: \(key)): \(error.localizedDescription)")
            #endif
            return
        }

        // 용량 초과 시 정리
        trimToSizeLimitIfNeeded()
    }

    /// 키에 해당하는 데이터를 디스크에서 조회한다.
    /// 만료된 항목은 자동 삭제 후 nil 반환 (Lazy Deletion).
    /// - Parameter key: 조회할 키
    /// - Returns: 저장된 데이터 또는 nil
    public func value(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = filePath(forKey: key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // 만료 확인
        if isExpired(at: fileURL) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    /// 특정 키의 항목을 디스크에서 제거한다.
    /// - Parameter key: 제거할 키
    public func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = filePath(forKey: key)
        try? fileManager.removeItem(at: fileURL)
    }

    /// 모든 캐시 파일을 제거한다.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 특정 키의 항목이 존재하는지 확인한다 (만료 확인 포함).
    /// - Parameter key: 확인할 키
    /// - Returns: 존재 여부
    public func isCached(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = filePath(forKey: key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        // 만료된 항목은 삭제 후 false 반환
        if isExpired(at: fileURL) {
            try? fileManager.removeItem(at: fileURL)
            return false
        }

        return true
    }

    /// 현재 디스크 캐시가 사용 중인 총 용량 (바이트)
    public var totalSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return calculateTotalSize()
    }

    /// 만료된 파일들을 일괄 정리한다.
    public func removeExpiredFiles() {
        lock.lock()
        defer { lock.unlock() }

        guard config.maxAge > 0 else { return }

        let fileURLs = contentsOfDirectory()
        for fileURL in fileURLs {
            if isExpired(at: fileURL) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - 내부 로직

    /// 키를 파일 경로로 변환한다.
    private func filePath(forKey key: String) -> URL {
        let hashedName = KeyHasher.sha256(key)
        return directory.appendingPathComponent(hashedName)
    }

    /// 파일의 수정 시각이 maxAge를 초과했는지 확인한다.
    private func isExpired(at fileURL: URL) -> Bool {
        guard config.maxAge > 0 else { return false }

        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true // 속성을 읽을 수 없으면 만료로 간주
        }

        return Date().timeIntervalSince(modificationDate) > config.maxAge
    }

    /// 용량 초과 시 오래된 파일부터 제거한다.
    ///
    /// 파일의 마지막 수정 시각 기준으로 정렬하여 삭제.
    /// totalCostLimit의 75% 이하가 될 때까지 삭제한다 (hysteresis 방지).
    ///
    /// 파일 목록 조회와 크기 계산을 한 번에 처리하여 중복 I/O를 방지한다.
    private func trimToSizeLimitIfNeeded() {
        guard config.totalCostLimit > 0 else { return }

        // 파일 목록과 속성을 한 번에 수집
        let fileURLs = contentsOfDirectory()
        let fileInfos = fileURLs.compactMap { fileURL -> (URL, Date, Int)? in
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let fileSize = attrs[.size] as? Int else {
                return nil
            }
            return (fileURL, modDate, fileSize)
        }

        var currentSize = fileInfos.reduce(0) { $0 + $1.2 }
        guard currentSize > config.totalCostLimit else { return }

        let targetSize = config.totalCostLimit * 3 / 4  // 75%까지 정리

        // 수정 시각 오름차순 정렬 (오래된 것부터 삭제)
        let sortedFiles = fileInfos.sorted { $0.1 < $1.1 }

        for (fileURL, _, fileSize) in sortedFiles {
            guard currentSize > targetSize else { break }
            try? fileManager.removeItem(at: fileURL)
            currentSize -= fileSize
        }
    }

    /// 디렉토리 내 모든 파일 URL을 반환한다.
    private func contentsOfDirectory() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? []
    }

    /// 디렉토리 내 전체 파일 크기를 계산한다 (바이트).
    ///
    /// prefetch된 `fileSizeKey` 속성을 사용하여 추가 I/O를 최소화한다.
    private func calculateTotalSize() -> Int {
        let fileURLs = contentsOfDirectory()
        return fileURLs.reduce(0) { total, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }
}
