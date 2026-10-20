import Foundation
import Testing
@testable import OS1

struct ProviderValidationClientTests {
    @Test(arguments: ["minimax", "minimax-cn"])
    func regionalModelRequestsPreferFlash(slug: String) async throws {
        let entry = try #require(ProviderCatalog.entry(for: slug))
        let result = try await validate(entry)
        #expect(!result.wasSkipped)
        #expect(result.models.map(\.id) == ["MiniMax-M3.1-Flash", "MiniMax-M3"])
        #expect(result.models.first?.contextLength == 1_000_000)
    }

    @Test
    func gatewayChoicesKeepGatewayMetadataAndOtherCapabilities() async throws {
        let entry = try #require(ProviderCatalog.entry(for: "openrouter"))
        let result = try await validate(entry)
        #expect(result.models.map(\.id) == [
            "minimax/minimax-m3.1-flash:free", "minimax/minimax-m3",
            "unrelated/model", "minimax/speech-02"
        ])
        // Deliberately different from the direct API: the gateway owns this value.
        #expect(result.models.first?.contextLength == 262_144)
    }

    @Test
    func unrelatedProviderKeepsItsCatalog() async throws {
        let entry = try #require(ProviderCatalog.entry(for: "openai"))
        let result = try await validate(entry)
        #expect(result.models.map(\.id) == ["custom-model", "legacy-model"])
    }

    @Test
    func missingPreferredModelsAreNotInvented() throws {
        for slug in ["minimax", "minimax-cn", "openrouter"] {
            let entry = try #require(ProviderCatalog.entry(for: slug))
            #expect(entry.modelChoices(from: []).isEmpty)
        }
    }

    private func validate(_ entry: ProviderCatalogEntry) async throws -> ProviderValidationResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await ProviderValidationClient(urlSession: session)
            .validate(apiKey: " fixture-key ", against: entry)
    }
}

/// Intercepts the real URLSession boundary; no provider credentials or network.
private final class ModelCatalogURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.httpBody == nil)
        let url = request.url!
        let body: String
        switch url.host {
        case "api.minimax.io", "api.minimaxi.com":
            #expect(url.path == "/v1/models")
            body = #"{"data":[{"id":"MiniMax-M2.7"},{"id":"MiniMax-M3"},{"id":"MiniMax-M3.1-Flash","context_length":1000000}]}"#
        case "openrouter.ai":
            #expect(url.path == "/api/v1/models")
            body = #"{"data":[{"id":"unrelated/model"},{"id":"minimax/minimax-m2.7"},{"id":"minimax/minimax-m3"},{"id":"minimax/minimax-m3.1-flash:free","context_length":262144},{"id":"minimax/speech-02"},{"id":"minimax/minimax-m3.1-flash"}]}"#
        case "api.openai.com":
            #expect(url.path == "/v1/models")
            body = #"{"data":[{"id":"custom-model"},{"id":"legacy-model"}]}"#
        default:
            Issue.record("Unexpected request host")
            body = #"{"data":[]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
