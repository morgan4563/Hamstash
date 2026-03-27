// HamstashCache.swift
// NSLock 기반 스레드 안전 캐시

import Foundation

/// 이미지 캐싱에 특화된 타입 별칭
///
/// ```swift
/// let imageCache = ImageCache(policy: .lru, capacity: 100)
/// imageCache.store(imageData, forKey: "profile_123")
/// ```
public typealias ImageCache = HamstashCache<String, Data>

/// Hamstash의 스레드 안전 캐시
///
/// 캐시 정책을 enum으로 선택하고, 멀티스레드 환경에서 안전하게 사용할 수 있다.
/// NSLock + defer 패턴으로 모든 접근을 직렬화한다.
///
/// ```swift
/// let cache = HamstashCache<String, Data>(policy: .lru, capacity: 100)
/// cache.store(imageData, forKey: "profile_123")     // 백그라운드 스레드에서
/// let data = cache.value(forKey: "profile_123")      // 메인 스레드에서 — 안전
/// ```
///
/// **설계 원칙**: 캐시 로직(LRU, LFU 등)과 동기화 로직(Lock)을 분리.
/// 개별 캐시 정책은 순수한 로직만 담당하고, 스레드 안전은 이 래퍼가 담당한다.
public final class HamstashCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    // MARK: - 캐시 정책 선택

    /// 사용 가능한 캐시 교체 정책
    public enum Policy {
        /// 가장 오래 사용하지 않은 항목부터 제거 (기본값, 가장 범용적)
        case lru
        /// 가장 적게 사용된 항목부터 제거 (자주 접근하는 항목 유지에 적합)
        case lfu
        /// 먼저 들어온 항목부터 제거 (순서대로 소비하는 데이터에 적합)
        case fifo
        /// 만료 시간이 지난 항목을 자동 제거
        case ttl(duration: TimeInterval = 300)
    }

    // MARK: - 프로퍼티

    private var policy: any CachePolicy<Key, Value>
    private let lock = NSLock()
    private let isTTLPolicy: Bool

    // MARK: - 초기화

    /// - Parameters:
    ///   - policy: 캐시 교체 정책
    ///   - capacity: 최대 저장 항목 수 (1 이상이어야 함)
    public init(policy: Policy, capacity: Int) {
        precondition(capacity > 0, "capacity는 1 이상이어야 합니다. 현재 값: \(capacity)")

        switch policy {
        case .lru:
            self.policy = LRUCache<Key, Value>(capacity: capacity)
            self.isTTLPolicy = false
        case .lfu:
            self.policy = LFUCache<Key, Value>(capacity: capacity)
            self.isTTLPolicy = false
        case .fifo:
            self.policy = FIFOCache<Key, Value>(capacity: capacity)
            self.isTTLPolicy = false
        case .ttl(let duration):
            precondition(duration > 0, "TTL duration은 0보다 커야 합니다. 현재 값: \(duration)")
            self.policy = TTLCache<Key, Value>(capacity: capacity, defaultTTL: duration)
            self.isTTLPolicy = true
        }
    }

    // MARK: - 캐시 조작

    /// 캐시에 값을 저장한다.
    public func store(_ value: Value, forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        policy.store(value, forKey: key)
    }

    /// TTL을 직접 지정해서 저장한다. (TTL 정책일 때만 개별 만료 시간이 적용됨)
    ///
    /// TTL 정책이 아닌 캐시에서 호출하면 ttl 파라미터는 무시되고 일반 store로 동작한다.
    /// (디버그 빌드에서 경고가 출력됨)
    ///
    /// - Parameters:
    ///   - value: 저장할 값
    ///   - key: 식별 키
    ///   - ttl: 만료 시간 (초)
    public func store(_ value: Value, forKey key: Key, ttl: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if var ttlPolicy = policy as? TTLCache<Key, Value> {
            ttlPolicy.store(value, forKey: key, ttl: ttl)
            policy = ttlPolicy
        } else {
            #if DEBUG
            print("⚠️ [Hamstash] ttl 파라미터는 TTL 정책에서만 의미가 있습니다. 현재 정책에서는 무시됩니다.")
            #endif
            policy.store(value, forKey: key)
        }
    }

    /// 키에 해당하는 값을 조회한다.
    public func value(forKey key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return policy.value(forKey: key)
    }

    /// 특정 키의 항목을 제거한다.
    public func remove(forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        policy.remove(forKey: key)
    }

    /// 모든 항목을 제거한다.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        policy.removeAll()
    }

    /// 현재 저장된 항목 수
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return policy.count
    }

    /// 최대 저장 가능 항목 수
    public var capacity: Int {
        policy.capacity
    }
}
