import Foundation

enum HomeWeather {
    struct Locations: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
            let country: String?
        }
        let results: [Place]?
    }
    struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]
            let weather_code: [Int?]
        }
        let current: Current
        let daily: Daily
    }

    static func request<T: Decodable>(_ host: String, path: String, params: [String:String]) async throws -> T {
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.path = path
        url.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let destination = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: destination)
        request.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = response as? HTTPURLResponse, status.statusCode == 200,
              data.count < 300_000 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "晴间多云"
        case 3: return "阴"
        case 45, 48: return "有雾"
        case 51...57: return "毛毛雨"
        case 61...67, 80...82: return "有雨"
        case 71...77, 85...86: return "有雪"
        case 95...99: return "雷雨"
        default: return "天气状况未知"
        }
    }

    static func reply(_ text: String) async -> String? {
        // Explicit everyday weather requests only; broader discussion remains with the AI.
        let pattern = #"^(?:请问|告诉我|帮我查一下|查一下|查查|查看)?\s*(.*?)(今天|明天|后天|现在|当前|今日)?(?:的)?(?:天气(?:预报|怎么样|如何)?|气温(?:多少|怎么样)?|多少度|会下雨吗|下雨吗|冷不冷|热不热)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let cityText = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
        let day = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        let city = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = city.isEmpty || ["当地","这里","家里","本地"].contains(city) ?
            (UserDefaults.standard.string(forKey: "homeWeatherCity") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : city
        guard !target.isEmpty else { return "还没有设置家庭天气城市。你可以说北京明天天气，或在助手中保存默认城市。" }
        guard target.count <= 60, target.rangeOfCharacter(from: .newlines) == nil else { return "请说出要查询的城市名称。" }
        do {
            let places: Locations = try await request("geocoding-api.open-meteo.com", path: "/v1/search",
                params: ["name":target, "count":"1", "language":"zh"])
            guard let place = places.results?.first else { return "没有找到这个城市，请换一个城市名称。" }
            let forecast: Forecast = try await request("api.open-meteo.com", path: "/v1/forecast",
                params: ["latitude":String(place.latitude), "longitude":String(place.longitude),
                         "current":"temperature_2m,apparent_temperature,weather_code",
                         "daily":"temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code",
                         "timezone":"auto","forecast_days":"3"])
            let location = [place.name, place.admin1, place.country].compactMap { $0 }.reduce(into: [String]()) { list, item in
                if !list.contains(item) { list.append(item) }
            }.joined(separator: "，")
            let index = day == "明天" ? 1 : day == "后天" ? 2 : 0
            let daily = forecast.daily
            guard daily.weather_code.indices.contains(index), daily.temperature_2m_min.indices.contains(index),
                  daily.temperature_2m_max.indices.contains(index), daily.precipitation_probability_max.indices.contains(index),
                  let code = daily.weather_code[index], let low = daily.temperature_2m_min[index],
                  let high = daily.temperature_2m_max[index] else { return "天气预报数据暂时不完整。" }
            let dateLabel = index == 1 ? "明天" : index == 2 ? "后天" : "今天"
            let rain = daily.precipitation_probability_max[index].map { "，最高降水概率百分之\($0)" } ?? ""
            let details = "\(dateLabel)\(description(code))，最低\(Int(low.rounded()))度，最高\(Int(high.rounded()))度\(rain)。"
            if index == 0 {
                let current = forecast.current
                return "\(location)，现在\(description(current.weather_code))，气温\(Int(current.temperature_2m.rounded()))度，体感\(Int(current.apparent_temperature.rounded()))度。\(details)"
            }
            return location + "，" + details
        } catch {
            return "天气服务暂时没有返回数据，请过一会儿再问。"
        }
    }
}
