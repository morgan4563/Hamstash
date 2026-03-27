// TTLCache.swift
// Time To Live — 만료 시간이 지난 항목을 자동 제거

import Foundation

/// TTL 캐시의 항목 (값 + 만료 시각)
struct TTLEntry<Value: Sendable>: Sendable {
    let value: Value
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

/// TTL 캐시
///
/// **자료구조**: Dictionary (키 → TTLEntry)
/// - 저장 시 현재 시각 + TTL로 만료 시각을 기록
/// - 조회 시 만료 확인 → 만료됐으면 삭제 후 nil 반환
///
/// **시간복잡도**: store O(1), value O(1), remove O(1)
///
/// **적합한 사용 시나리오**:
/// - 주기적으로 갱신되는 데이터 (날씨, 환율, 실시간 가격 등)
/// - 일정 시간 후 반드시 최신 데이터를 가져와야 하는 경우
///
/// **만료 전략**:
/// - Lazy: 조회 시 만료 확인 → 만료됐으면 삭제 후 nil 반환
/// - Eviction: 용량 초과 시 만료 항목 우선 정리, 그래도 부족하면 가장 빨리 만료되는 항목 제거
///
/// **단점**:
/// - 만료 전이라도 용량이 부족하면 어떤 항목을 제거할지 기준이 없음
///   (이 구현에서는 capacity 초과 시 만료된 항목을 우선 정리하고,
///    그래도 부족하면 가장 빨리 만료되는 항목을 제거)
struct TTLCache<Key: Hashable & Sendable, Value: Sendable> {

    private var map: [Key: TTLEntry<Value>] = [:]

    let capacity: Int

    /// 기본 TTL (초 단위)
    let defaultTTL: TimeInterval

    /// - Parameters:
    ///   - capacity: 최대 저장 항목 수
    ///   - defaultTTL: 기본 만료 시간 (초). 기본값 300초(5분)
    init(capacity: Int, defaultTTL: TimeInterval = 300) {
        self.capacity = capacity
        self.defaultTTL = defaultTTL
    }

    /// 만료된 항목들을 모두 제거한다.
    private mutating func removeExpired() {
        let expiredKeys = map.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredKeys {
            map.removeValue(forKey: key)
        }
    }

    /// 가장 빨리 만료되는 항목을 제거한다.
    private mutating func evictEarliestExpiring() {
        guard let earliest = map.min(by: { $0.value.expiresAt < $1.value.expiresAt }) else { return }
        map.removeValue(forKey: earliest.key)
    }
}

extension TTLCache: CachePolicy {

    var count: Int { map.count }

    mutating func store(_ value: Value, forKey key: Key) {
        store(value, forKey: key, ttl: defaultTTL)
    }

    /// TTL을 직접 지정해서 저장한다.
    /// - Parameters:
    ///   - value: 저장할 값
    ///   - key: 식별 키
    ///   - ttl: 만료 시간 (초). 0보다 커야 함
    mutating func store(_ value: Value, forKey key: Key, ttl: TimeInterval) {
        guard capacity > 0 else { return }

        precondition(ttl > 0, "ttl은 0보다 커야 합니다. 현재 값: \(ttl)")
        let safeTTL = ttl

        // 이미 존재하면 만료 시각 갱신
        if map[key] != nil {
            map[key] = TTLEntry(value: value, expiresAt: Date().addingTimeInterval(safeTTL))
            return
        }

        // 용량 초과 시: 만료 항목 우선 정리 → 그래도 부족하면 가장 빨리 만료되는 항목 제거
        if map.count >= capacity {
            removeExpired()
            if map.count >= capacity {
                evictEarliestExpiring()
            }
        }

        map[key] = TTLEntry(value: value, expiresAt: Date().addingTimeInterval(safeTTL))
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let entry = map[key] else { return nil }

        // 만료됐으면 삭제 후 nil 반환 (Lazy Deletion)
        if entry.isExpired {
            map.removeValue(forKey: key)
            return nil
        }

        return entry.value
    }

    mutating func remove(forKey key: Key) {
        map.removeValue(forKey: key)
    }

    mutating func removeAll() {
        map.removeAll()
    }
}
