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

    struct Intent {
        let city: String
        let day: String
        let advice: Bool
    }

    static func parse(_ text: String) -> Intent? {
        let pattern = #"^(?:请问|告诉我|帮我查一下|查一下|查查|查看)?\s*(今天|明天|后天|现在|当前|今日)?(.*?)(今天|明天|后天|现在|当前|今日)?(?:的)?(天气(?:预报|怎么样|如何)?|气温(?:多少|怎么样)?|多少度|会下雨吗|下雨吗|冷不冷|热不热|适合(?:出去玩|出门|散步|跑步|运动)吗|要带伞吗|需要带伞吗|要穿什么|怎么穿衣服|穿什么衣服(?:合适)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String {
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
        let city = group(2).trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject sentence-like inputs rather than send arbitrary private conversation to geocoding.
        guard city.count <= 30, !city.contains("我"), !city.contains("你"),
              !city.contains("因为"), !city.contains("如果"), !city.contains("。"),
              !city.contains("，"), !city.contains("的"),
              city.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let day = group(3).isEmpty ? group(1) : group(3)
        let purpose = group(4)
        return Intent(city: city, day: day,
                      advice: purpose.hasPrefix("适合") || purpose.contains("带伞") || purpose.contains("穿"))
    }

    static func advice(code: Int, low: Double, high: Double, rain: Int?) -> String {
        var parts: [String] = []
        if (95...99).contains(code) {
            parts.append("有雷雨预报，建议避免户外活动")
        } else if (71...77).contains(code) || (85...86).contains(code) {
            parts.append("可能下雪，出门留意路面湿滑")
        } else if let rain, rain >= 50 {
            parts.append("降水概率较高，建议带伞并准备室内备选")
        } else if (51...67).contains(code) || (80...82).contains(code) {
            parts.append("有雨的预报，出门可以带伞")
        } else if let rain, rain >= 30 {
            parts.append("有一定降水可能，可以带把折叠伞")
        }
        if high >= 32 {
            parts.append("高温时段注意防暑和补水")
        } else if high <= 10 || low <= 0 {
            parts.append("天气偏冷，建议穿保暖外套")
        } else if high - low >= 10 {
            parts.append("早晚温差较大，建议分层穿衣")
        } else if low < 15 {
            parts.append("可以准备一件薄外套")
        }
        if parts.isEmpty {
            return "从目前预报看，没有明显的高温、低温或降水信号；出门前可以再确认实时天气。"
        }
        return parts.joined(separator: "。") + "。具体活动还需结合实时天气和个人情况。"
    }

    static func reply(_ text: String) async -> String? {
        guard let intent = parse(text) else { return nil }
        let city = intent.city
        let day = intent.day
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
            let suggestion = intent.advice ? advice(code: code, low: low, high: high, rain: daily.precipitation_probability_max[index]) : ""
            if index == 0 {
                let current = forecast.current
                return "\(location)，现在\(description(current.weather_code))，气温\(Int(current.temperature_2m.rounded()))度，体感\(Int(current.apparent_temperature.rounded()))度。\(details)\(suggestion)"
            }
            return location + "，" + details + suggestion
        } catch {
            return "天气服务暂时没有返回数据，请过一会儿再问。"
        }
    }
}
