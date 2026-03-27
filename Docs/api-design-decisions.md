# API 설계 결정 기록

## 1. enum 기반 정책 선택

### 변경 전
```swift
// 사용자가 내부 타입을 직접 알아야 했음
let lru = LRUCache<String, Data>(capacity: 100)
let cache = ThreadSafeCache(policy: lru)
```

### 변경 후
```swift
let cache = HamstashCache<String, Data>(policy: .lru, capacity: 100)
```

### 이유
- 사용자가 내부 구현(LRUCache, LFUCache 등)을 알 필요 없이 enum으로 선택
- 자동완성에서 `.lru`, `.lfu`, `.fifo`, `.ttl(duration:)`만 보여줌
- 잘못된 조합(예: 존재하지 않는 정책) 불가능

---

## 2. precondition으로 잘못된 입력 차단

### 적용 위치
| 파라미터 | 조건 | 이유 |
|---------|------|------|
| `capacity` | `> 0` | 0 이하의 capacity는 캐시의 의미가 없음. 실수를 빨리 발견하도록 |
| `TTL duration` | `> 0` | 0 이하의 TTL은 즉시 만료 → 저장 의미 없음 |
| `store(ttl:)` | `> 0` | 개별 TTL도 마찬가지 |

### 이전 방식 (clamping)
```swift
// TTL=0 → 1초로 자동 보정
self.defaultTTL = defaultTTL > 0 ? defaultTTL : 1
```

### 변경 이유
- 자동 보정은 버그를 숨김 → 개발자가 의도하지 않은 동작 발생 가능
- `precondition`은 릴리즈 빌드에서도 크래시 → 빠른 발견
- 라이브러리에서는 "잘못 쓰면 바로 알려주는 것"이 더 안전

---

## 3. TTL 오용 방지 (DEBUG 경고)

### 문제
TTL이 아닌 정책(LRU, LFU, FIFO)에서 `store(_:forKey:ttl:)`을 호출하면 ttl이 무시됨.
사용자는 ttl이 적용된 줄 알고 넘어갈 수 있음.

### 해결
```swift
#if DEBUG
print("⚠️ [Hamstash] ttl 파라미터는 TTL 정책에서만 의미가 있습니다.")
#endif
policy.store(value, forKey: key)  // ttl 무시하고 일반 store
```

### assertionFailure를 쓰지 않은 이유
- `assertionFailure`는 디버그 빌드에서 크래시 → 테스트 실행 불가
- 동작 자체는 정의되어 있으므로 (일반 store로 폴백) 크래시까지는 불필요
- DEBUG 콘솔 경고로 개발자에게 충분히 알림

---

## 4. ImageCache 타입 별칭

```swift
public typealias ImageCache = HamstashCache<String, Data>
```

### 이유
- 이미지 캐싱이 가장 흔한 사용 사례
- `HamstashCache<String, Data>` 반복 타이핑 방지
- 사용 예: `let cache = ImageCache(policy: .lru, capacity: 100)`

---

## 5. public 접근 제어

### public으로 공개한 것
- `HamstashCache` 클래스
- `HamstashCache.Policy` enum
- `ImageCache` typealias
- `init(policy:capacity:)`
- `store`, `value`, `remove`, `removeAll`
- `count`, `capacity`

### internal로 유지한 것 (외부 비공개)
- `CachePolicy` 프로토콜
- `LRUCache`, `LFUCache`, `FIFOCache`, `TTLCache`
- `DoublyLinkedList`, `Node`, `FrequencyBucket`

### 이유
- 사용자는 `HamstashCache`와 `Policy` enum만 알면 됨
- 내부 구현을 숨겨서 추후 변경 자유도 확보
- 잘못된 직접 사용 방지

---

## 6. 내부 정책의 capacity=0 guard 유지

`HamstashCache`에서 `precondition(capacity > 0)`으로 막지만,
내부 정책(LRU, LFU, FIFO, TTL)에도 `guard capacity > 0`을 유지.

### 이유
- 내부 정책은 독립적으로 테스트됨
- 방어적 프로그래밍: 래퍼 없이 내부 타입을 직접 쓸 수도 있음
- 이중 안전장치
