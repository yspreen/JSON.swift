//
//  Rest.swift
//  www.spreen.co
//
//  Created by Nick on 8/20/23.
//

import Foundation

fileprivate extension NSMutableData {
	func append(string: String) {
		append(string.data(using: .utf8) ?? .init())
	}
}

fileprivate extension Data {
	func toMultiPart(_ boundary: String, fileName: String) -> Data {
		let fieldData = NSMutableData()
		fieldData.append(string: "--\(boundary)\r\n")
		fieldData.append(string: "Content-Disposition: form-data; name=\"\(fileName)\"; filename=\"\(fileName)\"\r\n")
		fieldData.append(string: "Content-Type: application/octet-stream\r\n\r\n")
		fieldData.append(self)
		fieldData.append(string: "\r\n--\(boundary)--\r\n")
		return fieldData as Data
	}
}

public struct Rest {
	let boundary = { "--\((0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined())" }()

	public static var shared = Rest()

	public static var noInternet = false

	@discardableResult
	public func get(url: String, with params: JSONDict? = [:]) async -> JSON? {
		await jsonRequest(
			method: "GET", url: url, with: params as Any, hasBody: false
		)
	}

	@discardableResult
	public func delete(url: String, with params: JSONDict? = [:]) async -> JSON? {
		await jsonRequest(
			method: "DELETE", url: url, with: params as Any, hasBody: false
		)
	}

	@discardableResult
	public func post(url: String, with params: JSONDict? = [:]) async -> JSON? {
		await jsonRequest(
			method: "POST", url: url, with: params as Any, hasBody: true
		)
	}

	@discardableResult
	public func put(url: String, with params: JSONDict? = [:]) async -> JSON? {
		await jsonRequest(
			method: "PUT", url: url, with: params as Any, hasBody: true
		)
	}

	@discardableResult
	public func post(url: String, with data: Data, and contentType: String) async -> JSON? {
		await jsonRequest(
			method: "POST", url: url, with: data as Any, hasBody: true, contentType: contentType
		)
	}

	@discardableResult
	public func uploadFile(to url: String, with data: Data?, and fileName: String) async -> JSON? {
		guard let data = data else { return nil }
		return await jsonRequest(
			method: "POST",
			url: url,
			with: data.toMultiPart(boundary, fileName: fileName) as Any,
			hasBody: true,
			contentType: "application/octet-stream"
		) {
			var request = $0
			request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
			return request
		}
	}

	var authMiddleware: (URLRequest) async -> URLRequest? = { $0 }
	var urlMiddleware: (String) async -> URL? = { URL(string: $0) }

	public func jsonRequest(
		method: String,
		url: String,
		with params: Any,
		hasBody: Bool,
		contentType: String = "application/json",
		modifyRequest: ((URLRequest) -> URLRequest)? = nil
	) async -> JSON? {
		guard
			let (data, statusCode) = await request(
				method: method,
				url: url,
				with: params,
				hasBody: hasBody,
				contentType: contentType,
				modifyRequest: modifyRequest
			)
		else {
			return nil
		}
		return JSON(data: data)?.tagged(statusCode)
	}

	@discardableResult
	public func download(url: String, to localPath: URL) async -> Bool {
		guard
			let (data, _) = await request(
				method: "get",
				url: url,
				with: [:] as [String: String],
				hasBody: false
			)
		else { return false }
		let res: ()? = try? data.write(to: localPath)
		return res != nil
	}

	public func request(
		method: String,
		url: String,
		with params: Any,
		hasBody: Bool,
		contentType: String = "application/json",
		modifyRequest: ((URLRequest) -> URLRequest)? = nil
	) async -> (Data, Int)? {
		var path = url
		if !hasBody, let params = params as? JSONDict {
			path += "?"
			var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
			allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
			for (key_, value__) in params {
				var value_ = value__
				if
					let base = value_.base as? Optional<AnyHashable>,
					let unwrap = base
				{
					value_ = unwrap
				}
				guard
					let key = key_.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey),
					let value = "\(value_)".addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey)
				else {
					fatalError("")
				}
				path += "\(key)=\(value)&"
			}
			path.removeLast()
		}
		guard let url = await urlMiddleware(path) else {
			return nil
		}

		var request: URLRequest? = URLRequest(url: url)
		request?.httpMethod = method
		request?.timeoutInterval = 60
		guard request != nil else { return nil }
		request = await authMiddleware(request!)

		if hasBody {
			request?.setValue(contentType, forHTTPHeaderField: "Content-Type")
		}

		guard request != nil else { return nil }
		request = (modifyRequest ?? { $0 })(request!)
		guard request != nil else { return nil }

		do {
			let result = try await getResult(
				for: request!,
				params: params,
				hasBody: hasBody
			)
			Self.noInternet = false
			return (result.0, (result.1 as? HTTPURLResponse)?.statusCode ?? -1)
		} catch {
			var wait = false
			switch (error as? URLError)?.code ?? .unknown {
			case .backgroundSessionWasDisconnected:
				wait = true
			case .cannotConnectToHost:
				wait = true
			case .cannotFindHost:
				wait = true
			case .cannotLoadFromNetwork:
				wait = true
			case .dnsLookupFailed:
				wait = true
			case .networkConnectionLost:
				wait = true
			case .notConnectedToInternet:
				wait = true
			case .timedOut:
				wait = true
			default:
				break
			}
			Self.noInternet = wait
			if wait { try? await Task.sleep(for: .seconds(1)) }
			return nil
		}
	}

	func getResult(
		for request: URLRequest,
		params: Any,
		hasBody: Bool
	) async throws -> (Data, URLResponse) {
		if hasBody, let params = params as? JSONDict {
			let payload = (try? JSONSerialization.data(withJSONObject: params)) ?? .init()
			return try await URLSession.shared.upload(for: request, from: payload)
		} else if hasBody, let data = params as? Data {
			return try await URLSession.shared.upload(for: request, from: data)
		} else {
			return try await URLSession.shared.data(for: request)
		}
	}
}
