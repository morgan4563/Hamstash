# Hamstash

Swift 기반 이미지 캐싱 라이브러리. 메모리 + 디스크 2단계 캐시, 네트워크 다운로드, SwiftUI/UIKit 지원.

## 요구사항

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- 외부 의존성 없음

## 설치

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/{사용자명}/Hamstash.git", from: "1.0.0")
]
```

또는 Xcode에서 **File → Add Package Dependencies** → 저장소 URL 입력

> `import Hamstash` 하나로 모든 기능을 사용할 수 있다. SwiftUI, UIKit 별도 import 불필요.

---

## 빠른 시작

### SwiftUI

```swift
import Hamstash

struct ProfileView: View {
    let imageURL: URL

    var body: some View {
        HamstashImage(imageURL)
            .placeholder { ProgressView() }
            .fade(duration: 0.25)
            .aspectRatio(contentMode: .fill)
            .frame(width: 80, height: 80)
            .clipShape(Circle())
    }
}
```

### UIKit

```swift
import Hamstash

class ProfileCell: UITableViewCell {
    @IBOutlet weak var profileImageView: UIImageView!

    func configure(with url: URL) {
        profileImageView.hm.setImage(
            with: url,
            placeholder: UIImage(named: "placeholder")
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.hm.cancelDownload()
    }
}
```

---

## 주요 기능

### 1. 2단계 캐시 (메모리 + 디스크)

조회 순서: **Pin → 메모리 → 디스크 → 네트워크**

```swift
let storage = HamstashStorage.default

// 저장
storage.store(imageData, forKey: "profile_123")

// 조회 (메모리에 없으면 디스크에서 찾아 메모리로 올림)
let data = storage.value(forKey: "profile_123")

// 네트워크 다운로드 + 자동 캐싱
let data = try await storage.image(from: url)
```

### 2. 캐시 정책 선택

```swift
// LRU: 가장 오래 안 쓴 항목부터 제거 (기본값, 가장 범용적)
HamstashStorage(memoryPolicy: .lru, memoryCapacity: 100)

// LFU: 가장 적게 쓴 항목부터 제거 (자주 쓰는 이미지 유지에 적합)
HamstashStorage(memoryPolicy: .lfu, memoryCapacity: 100)

// FIFO: 먼저 들어온 항목부터 제거
HamstashStorage(memoryPolicy: .fifo, memoryCapacity: 100)

// TTL: 만료 시간이 지나면 자동 제거
HamstashStorage(memoryPolicy: .ttl(duration: 300), memoryCapacity: 100)
```

### 3. 디스크 캐시 설정

```swift
let storage = HamstashStorage(
    diskConfig: .init(
        name: "images",
        totalCostLimit: .megabytes(150),  // 150MB 제한
        maxAge: 7 * 24 * 60 * 60         // 7일 후 만료
    )
)
```

`ByteSize` 단위:
- `.kilobytes(500)` — 500KB
- `.megabytes(150)` — 150MB
- `.gigabytes(1)` — 1GB
- `.unlimited` — 제한 없음

### 4. 저장 옵션

```swift
// 메모리 + 디스크 양쪽 (기본값)
storage.store(data, forKey: "key", option: .memoryAndDisk)

// 메모리에만 (앱 종료 시 사라짐)
storage.store(data, forKey: "key", option: .memoryOnly)

// 디스크에만 (메모리 절약)
storage.store(data, forKey: "key", option: .diskOnly)
```

### 5. 헤더가 필요한 이미지 다운로드

```swift
// SwiftUI
var request = URLRequest(url: url)
request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
HamstashImage(request: request)

// UIKit
imageView.hm.setImage(request: request)

// 직접 다운로드
let data = try await storage.image(request: request)
```

### 6. Named Cache (용도별 캐시 분리)

같은 이름이면 같은 인스턴스를 반환한다. 데이터는 이름별로 격리된다.

```swift
let profileCache = HamstashStorage.named("profile")
let thumbnailCache = HamstashStorage.named("thumbnail", memoryCapacity: 200)

profileCache.store(data, forKey: "user1")
thumbnailCache.value(forKey: "user1")  // nil — 서로 격리됨
```

### 7. Pin (고정 항목)

고정된 항목은 LRU/LFU 등 캐시 정책에 의해 제거되지 않는다.
앱 로고, 자주 쓰는 아이콘 등에 사용한다.

```swift
storage.pin(logoData, forKey: "app_logo")

// 메모리를 비워도 고정 항목은 유지됨
storage.clearMemory()
storage.value(forKey: "app_logo")  // 여전히 존재

// 고정 해제 (일반 캐시로 이동)
storage.unpin(forKey: "app_logo")

// 고정 해제 (메모리에서 제거, 디스크에는 남음)
storage.unpin(forKey: "app_logo", keepInCache: false)
```

### 8. 캐시 통계

```swift
let stats = storage.statistics

stats.memoryHitCount  // 메모리에서 찾은 횟수
stats.diskHitCount    // 디스크에서 찾은 횟수
stats.missCount       // 못 찾은 횟수
stats.hitRate         // 히트율 (0.0 ~ 1.0)

storage.resetStatistics()  // 카운터 초기화
```

### 9. 캐시 관리

```swift
storage.clearMemory()              // 메모리만 비우기
storage.clearDisk()                // 디스크만 비우기
storage.clearAll()                 // 전부 비우기 (Pin 포함)

storage.remove(forKey: "key")      // 특정 항목 제거
storage.isCached(forKey: "key")    // 존재 여부 확인
storage.removeExpiredDiskFiles()   // 만료된 디스크 파일 정리

storage.diskSize                   // 현재 디스크 사용량 (바이트)
```

---

## SwiftUI API

```swift
HamstashImage(url)
    .placeholder { ProgressView() }           // 로딩 중 표시할 뷰
    .onFailureImage { Image(systemName: "photo") }  // 실패 시 표시할 뷰
    .resizable()                              // 이미지 크기 조절 (기본: true)
    .aspectRatio(contentMode: .fill)          // 콘텐츠 모드
    .fade(duration: 0.25)                     // 페이드 인 애니메이션
    .onSuccess { data in print("loaded") }    // 성공 콜백
    .onFailure { error in print("failed") }   // 실패 콜백
```

## UIKit API

```swift
// URL로 이미지 로딩
imageView.hm.setImage(with: url)

// placeholder + 콜백
imageView.hm.setImage(
    with: url,
    placeholder: UIImage(named: "placeholder")
) { result in
    switch result {
    case .success(let image): print("loaded")
    case .failure(let error): print("failed: \(error)")
    }
}

// URLRequest (헤더 포함)
imageView.hm.setImage(request: request)

// 다운로드 취소
imageView.hm.cancelDownload()
```

---

## 에러 처리

네트워크 API(`image(from:)`, `image(request:)`)에서 발생할 수 있는 에러:

```swift
do {
    let data = try await storage.image(from: url)
} catch let error as DownloadError {
    switch error {
    case .invalidResponse(let statusCode):
        print("서버 에러: \(statusCode)")      // 404, 500 등
    case .emptyData:
        print("응답 데이터가 비어있음")
    case .invalidURL:
        print("URL이 유효하지 않음")
    case .invalidImageData:
        print("이미지 형식이 아닌 데이터")
    }
}
```

---

## 자동 관리 (iOS)

별도 설정 없이 자동으로 동작한다:

- **메모리 부족 경고** → 메모리 캐시 자동 비움 (고정 항목 제외)
- **백그라운드 전환** → 만료된 디스크 파일 자동 정리

---

## 아키텍처

```
HamstashImage / imageView.hm     ← 사용자 API (SwiftUI / UIKit)
         │
    HamstashStorage               ← 2단계 캐시 + 통계 + Pin
         │
    ┌────┴────┐
    │         │
ImageCache  DiskCache             ← 메모리 (LRU/LFU/FIFO/TTL) + 디스크
    │
ImageDownloader                   ← URLSession 기반 + 중복 요청 병합
```

| 계층 | 역할 |
|------|------|
| `HamstashImage` | SwiftUI 선언형 이미지 뷰 |
| `UIImageView.hm` | UIKit 이미지 로딩 extension |
| `HamstashStorage` | 메모리+디스크 통합, 통계, Pin, Named Cache |
| `ImageCache` | 메모리 캐시 (4가지 교체 정책) |
| `DiskCache` | 파일 기반 디스크 캐시 (용량 제한, TTL) |
| `ImageDownloader` | 네트워크 다운로드 + 중복 요청 자동 병합 |

---

## 전체 API 레퍼런스

### HamstashStorage

```swift
// 공유 인스턴스
HamstashStorage.default

// Named Cache
HamstashStorage.named(_ name: String, memoryPolicy:, memoryCapacity:, diskTotalCostLimit:, diskMaxAge:)
HamstashStorage.removeNamed(_ name: String)
HamstashStorage.removeAllNamed()

// 커스텀 생성
HamstashStorage(
    memoryPolicy: .lru,          // .lru | .lfu | .fifo | .ttl(duration:)
    memoryCapacity: 100,
    diskConfig: DiskCache.Configuration(
        name: "images",
        totalCostLimit: .megabytes(150),  // DiskCache.ByteSize
        maxAge: 604800                    // TimeInterval (초)
    ),
    downloader: .default
)

// 저장/조회/삭제
store(_ data: Data, forKey: String, option: StorageOption = .memoryAndDisk)
value(forKey: String) -> Data?
remove(forKey: String)
isCached(forKey: String) -> Bool

// 네트워크 + 캐싱 (async)
image(from: URL) async throws -> Data
image(request: URLRequest) async throws -> Data

// 캐시 비우기
clearMemory()     // 메모리만 (Pin 유지)
clearDisk()       // 디스크만
clearAll()        // 전부 (Pin 포함)

// Pin
pin(_ data: Data, forKey: String)
unpin(forKey: String, keepInCache: Bool = true)
isPinned(forKey: String) -> Bool
unpinAll()
pinnedCount: Int

// 통계
statistics: CacheStatistics    // .memoryHitCount, .diskHitCount, .missCount, .hitRate
resetStatistics()

// 디스크 관리
removeExpiredDiskFiles()
diskSize: Int
```

### HamstashImage (SwiftUI)

```swift
HamstashImage(_ url: URL?, storage: HamstashStorage = .default)
HamstashImage(request: URLRequest, storage: HamstashStorage = .default)

// Builder 메서드 (체이닝)
.placeholder { View }
.onFailureImage { View }
.resizable(_ : Bool = true)
.aspectRatio(contentMode: ContentMode)
.fade(duration: Double = 0.25)
.onSuccess { (Data) -> Void }
.onFailure { (Error) -> Void }
```

### UIImageView Extension (UIKit)

```swift
imageView.hm.setImage(with: URL?, placeholder: UIImage?, storage: HamstashStorage, completion: ((Result<UIImage, Error>) -> Void)?)
imageView.hm.setImage(request: URLRequest, placeholder: UIImage?, storage: HamstashStorage, completion: ((Result<UIImage, Error>) -> Void)?)
imageView.hm.cancelDownload()
```

### DownloadError

```swift
case invalidResponse(statusCode: Int)  // HTTP 200번대 아닌 응답
case emptyData                          // 빈 응답 데이터
case invalidURL                         // 유효하지 않은 URL
case invalidImageData                   // 이미지로 변환 불가
```

---

## 테스트

```bash
swift test
```

149개 테스트, 33개 Suite:
- 캐시 정책 (LRU, LFU, FIFO, TTL)
- 디스크 캐시 (저장/조회/용량/만료/동시성)
- 네트워크 다운로더 (에러/중복 요청 병합)
- 2단계 캐시 (promote, 저장 옵션, 동시성)
- 캐시 통계 (히트/미스/히트율)
- Named Cache (인스턴스 격리)
- Pin (고정/해제/eviction 면역)

## 라이선스

MIT
