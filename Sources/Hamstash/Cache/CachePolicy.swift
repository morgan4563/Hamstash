// CachePolicy.swift
// 캐시 교체 정책의 공통 인터페이스 정의

/// 캐시 교체 정책 프로토콜
///
/// 모든 캐시 정책(LRU, LFU, FIFO, TTL)이 준수해야 하는 인터페이스.
/// 제네릭으로 설계되어 이미지뿐 아니라 Data 등 다양한 타입을 캐싱할 수 있다.
///
/// - Key: 캐시 항목을 식별하는 키 (Hashable, Sendable)
/// - Value: 캐시에 저장할 값 (Sendable)
protocol CachePolicy<Key, Value> {
    associatedtype Key: Hashable & Sendable
    associatedtype Value: Sendable

    /// 캐시에 값을 저장한다.
    /// 용량 초과 시 정책에 따라 기존 항목을 제거한 뒤 저장한다.
    /// - Parameters:
    ///   - value: 저장할 값
    ///   - key: 식별 키
    mutating func store(_ value: Value, forKey key: Key)

    /// 키에 해당하는 값을 조회한다.
    /// 정책에 따라 접근 기록이 갱신될 수 있다 (예: LRU는 최근 사용으로 갱신).
    /// - Parameter key: 조회할 키
    /// - Returns: 값이 존재하면 반환, 없으면 nil
    mutating func value(forKey key: Key) -> Value?

    /// 특정 키의 항목을 캐시에서 제거한다.
    /// - Parameter key: 제거할 키
    mutating func remove(forKey key: Key)

    /// 캐시의 모든 항목을 제거한다.
    mutating func removeAll()

    /// 현재 캐시에 저장된 항목 수
    var count: Int { get }

    /// 최대 저장 가능 항목 수
    var capacity: Int { get }
}
