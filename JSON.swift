//
//  JSON.swift
//  www.spreen.co
//
//  Created by Nick on 8/20/23.
//

import Foundation

public typealias JSONDict = [String: AnyHashable]

public struct JSON {
	public var value: AnyHashable
	public var tag: Int?

	public init(_ value: AnyHashable, tag: Int? = nil) {
		self.value = value
		self.tag = tag
	}

	static var empty: JSON {
		JSON(JSONDict())
	}

	public init?(parse input: Any?) {
		guard let input = input else { return nil }
		if let parsed = input as? JSONDict {
			value = parsed
		} else if let parsed = input as? Int {
			value = parsed
		} else if let parsed = input as? Int64 {
			value = parsed
		} else if let parsed = input as? String {
			value = parsed
		} else if let parsed = input as? Double {
			value = parsed
		} else if let parsed = input as? [JSONDict] {
			value = parsed
		} else if let parsed = input as? [Int] {
			value = parsed
		} else if let parsed = input as? [Int64] {
			value = parsed
		} else if let parsed = input as? [String] {
			value = parsed
		} else if let parsed = input as? [Double] {
			value = parsed
		} else if let parsed = input as? [[String]] {
			value = parsed
		} else if let parsed = input as? [AnyHashable] {
			value = parsed
		} else {
			return nil
		}
	}

	public init?(data: Data) {
		var value: Any?
		value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed]))
		if value == nil {
			value = String(data: data, encoding: .utf8)
		}
		guard let parsed = JSON(parse: value) else {
			return nil
		}
		self.value = parsed.value
	}

	public init?(string: String) {
		guard
			let data = string.data(using: .utf8),
			let parsed = JSON(data: data)
		else {
			return nil
		}
		self.value = parsed.value
	}

	public var dict: JSONDict? {
		value as? JSONDict
	}

	public var string: String? {
		value as? String
	}
	public var double: Double? {
		value as? Double
	}
	public var float: Float? {
		guard let double = value as? Double else {
			return nil
		}
		return Float(double)
	}
	public var int64: Int64? {
		value as? Int64
	}
	public var int: Int? {
		value as? Int
	}
	public var bool: Bool? {
		value as? Bool
	}
	public var date: Date? {
		(value as? Date) ?? Date(isoString: (value as? String) ?? "")
	}
	public var stringArray: [String]? {
		value as? [String]
	}
	public var doubleArray: [Double]? {
		value as? [Double]
	}
	public var jsonArray: [JSON]? {
		(value as? [Any])?.map { JSON.init(parse: $0) ?? .empty }
	}
	public var anyArray: [Any]? {
		value as? [Any]
	}
	public var jsonDictArray: [JSONDict]? {
		value as? [JSONDict]
	}

	public subscript(path: String) -> JSON {
		get {
			.init(dict?[path] as AnyHashable)
		}
		set {
			var jsonValue = dict ?? [:]
			jsonValue[path] = newValue.value
			value = jsonValue
		}
	}

	public var jsonStringData: Data {
		(try? JSONSerialization.data(
			withJSONObject: Self.encodeAllDates(for: value),
			options: [.fragmentsAllowed]
		)) ?? "{}".data(using: .utf8)!
	}

	public var jsonString: String {
		String(data: jsonStringData, encoding: .utf8) ?? "{}"
	}

	func tagged(_ tag: Int) -> JSON {
		JSON(self.value, tag: tag)
	}

	public var isEmpty: Bool {
		dict?.count == 0
	}

	static func encodeAllDates(for value: AnyHashable) -> AnyHashable {
		if let date = value as? Date {
			return date.isoString
		}
		if let array = value as? [AnyHashable] {
			return array.map { encodeAllDates(for: $0) }
		}
		if let dict = value as? JSONDict {
			var newDict = JSONDict()
			for (key, value) in dict {
				newDict[key] = encodeAllDates(for: value)
			}
			return newDict
		}
		return value
	}
}

extension JSON: Encodable {
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(jsonStringData)
	}
}

fileprivate let Gregorian = Calendar(identifier: .gregorian)
fileprivate extension Date {
	static func newIsoFormatter() -> DateFormatter {
		let dateTimeFormatter = DateFormatter()
		dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		dateTimeFormatter.locale = Locale.current
		dateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
		return dateTimeFormatter
	}
	static let isoFormatter = { Self.newIsoFormatter() }()

	var isoString: String {
		let nano = (Gregorian.dateComponents(.init([
			.nanosecond
		]), from: self).nanosecond ?? 0) + 500
		return Date.isoFormatter.string(from: self)
			.replacingOccurrences(of: "Z", with: String(format: ".%06dZ", (nano / 1000) % 1000000))
	}

	init?(isoString str: String) {
		let fullSeconds = str.replacing(/\.\d+/, with: "")
		var nano = str.replacing(/^.*?\.(\d+).*?$/, with: { $0.output.1 })
		guard let date = Self.isoFormatter.date(from: fullSeconds) else {
			return nil
		}
		if !str.contains(".") {
			self = date
			return
		}
		while nano.count < 9 {
			nano += "0"
		}
		var components = Gregorian.dateComponents([
			.year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone
		], from: date)
		components.nanosecond = Int(nano)
		guard let fullDate = Gregorian.date(from: components) else {
			return nil
		}
		self = fullDate
	}
}
