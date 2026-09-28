import Foundation

public struct PlaceText: Decodable, Sendable {
  public var text: String
  public var languageCode: String?
}
public struct ReviewAuthor: Decodable, Sendable {
  public var displayName: String?
  public var uri: String?
  public var photoUri: String?
}
public struct PlaceReview: Decodable, Identifiable, Sendable {
  public var name: String?
  public var relativePublishTimeDescription: String?
  public var text: PlaceText?
  public var originalText: PlaceText?
  public var rating: Double?
  public var authorAttribution: ReviewAuthor?
  public var googleMapsUri: String?
  public var publishTime: String?
  public var visitDate: VisitDate?
  public var id: String {
    name ?? ((authorAttribution?.displayName ?? "") + (publishTime ?? "") + (text?.text ?? ""))
  }
  public struct VisitDate: Decodable, Sendable {
    public var year: Int?
    public var month: Int?
  }
}
public struct PlaceAttribution: Decodable, Sendable {
  public var provider: String?
  public var providerUri: String?
}
public struct GooglePlace: Decodable, Identifiable, Sendable {
  public var id: String
  public var displayName: PlaceText?
  public var formattedAddress: String?
  public var googleMapsUri: String?
  public var parkingOptions: [String: Bool]?
  public var reviews: [PlaceReview]?
  public var rating: Double?
  public var userRatingCount: Int?
  public var attributions: [PlaceAttribution]?
  public var parkingLines: [String] {
    let labels = [
      ("freeParkingLot", "무료 주차장"), ("paidParkingLot", "유료 주차장"), ("freeStreetParking", "무료 노상 주차"),
      ("paidStreetParking", "유료 노상 주차"), ("freeGarageParking", "무료 실내 주차"),
      ("paidGarageParking", "유료 실내 주차"), ("valetParking", "발레파킹"),
    ]
    return labels.compactMap { key, label in
      guard let available = parkingOptions?[key] else { return nil }
      return "\(label): \(available ? "제공":"제공하지 않음")"
    }
  }
}
public struct PlacesClient: Sendable {
  private let key: String
  private let session: URLSession
  public init(key: String, session: URLSession? = nil) {
    self.key = key
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.ephemeral
      config.urlCache = nil
      config.requestCachePolicy = .reloadIgnoringLocalCacheData
      self.session = URLSession(configuration: config)
    }
  }
  public func searchRequest(place: String, address: String) throws -> URLRequest {
    guard !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PlanError.invalid("장소 이름을 입력해 주세요.")
    }
    var request = URLRequest(
      url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
    request.setValue(
      "places.id,places.displayName,places.formattedAddress,places.googleMapsUri,places.attributions",
      forHTTPHeaderField: "X-Goog-FieldMask")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "textQuery": "\(place) \(address)", "languageCode": "ko", "regionCode": "KR", "pageSize": 5,
    ])
    request.timeoutInterval = 20
    return request
  }
  public func detailsRequest(id: String) throws -> URLRequest {
    guard id.range(of: #"^[A-Za-z0-9_-]{1,255}$"#, options: .regularExpression) != nil else {
      throw PlanError.invalid("장소 연결 정보를 확인해 주세요.")
    }
    var url = URLComponents(string: "https://places.googleapis.com/v1/places/\(id)")!
    url.queryItems = [URLQueryItem(name: "languageCode", value: "ko")]
    var request = URLRequest(url: url.url!)
    request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
    request.setValue(
      "id,displayName,formattedAddress,googleMapsUri,parkingOptions,reviews,rating,userRatingCount,attributions",
      forHTTPHeaderField: "X-Goog-FieldMask")
    request.timeoutInterval = 20
    return request
  }
  public func search(place: String, address: String) async throws -> [GooglePlace] {
    struct Result: Decodable { var places: [GooglePlace]? }
    return try await fetch(Result.self, request: searchRequest(place: place, address: address))
      .places ?? []
  }
  public func details(id: String) async throws -> GooglePlace {
    try await fetch(GooglePlace.self, request: detailsRequest(id: id))
  }
  private func fetch<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw PlanError.invalid("외부 장소 정보에 연결하지 못했습니다.")
    }
    switch response.statusCode {
    case 200..<300: break
    case 401, 403: throw PlanError.invalid("API 키, Places API (New) 활성화 및 결제 설정을 확인해 주세요.")
    case 429: throw PlanError.invalid("조회 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.")
    case 404: throw PlanError.invalid("연결된 장소를 찾을 수 없습니다. 장소를 다시 선택해 주세요.")
    default: throw PlanError.invalid("장소 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
}
