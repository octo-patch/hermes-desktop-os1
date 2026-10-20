import Foundation
import Testing
@testable import OS1

struct ProviderCatalogTests {
    @Test
    func slugsAreUnique() {
        let slugs = ProviderCatalog.entries.map(\.slug)
        let unique = Set(slugs)
        #expect(slugs.count == unique.count, "Slugs should be unique. Got: \(slugs)")
    }

    @Test
    func envVarsAreUnique() {
        // Hermes reads env vars from .env keyed by name, so two
        // providers writing to the same key would collide on disk.
        let envVars = ProviderCatalog.entries.map(\.envVar)
        let unique = Set(envVars)
        #expect(envVars.count == unique.count, "Env vars should be unique. Got: \(envVars)")
    }

    @Test
    func customProviderConfigNamesAreUnique() {
        // Within `custom_providers`, `name` is the lookup key — must be
        // unique. Built-in providers don't share this namespace.
        var names: [String] = []
        for entry in ProviderCatalog.entries {
            if case .customProvider(let configName) = entry.kind {
                names.append(configName)
            }
        }
        #expect(names.count == Set(names).count, "Custom provider names should be unique. Got: \(names)")
    }

    @Test
    func everyEntryHasParsableURLs() {
        for entry in ProviderCatalog.entries {
            #expect(entry.baseURL.scheme == "https",
                    "\(entry.slug) base URL should be https")
            #expect(entry.dashboardURL.scheme == "https",
                    "\(entry.slug) dashboard URL should be https")
            if let docs = entry.docsURL {
                #expect(docs.scheme == "https",
                        "\(entry.slug) docs URL should be https")
            }
        }
    }

    @Test
    func sixCoreProvidersPresent() {
        let expected: Set<String> = ["anthropic", "openrouter", "openai", "fireworks", "kimi", "zai"]
        let actual = Set(ProviderCatalog.entries.map(\.slug))
        #expect(expected.isSubset(of: actual), "Missing one of the 6 core providers. Got: \(actual)")
    }

    @Test
    func openRouterIsTheOnlyOAuthProvider() {
        // OAuth (PKCE) is OpenRouter-only today. If we add another
        // OAuth-capable provider this test should be loosened — but
        // the change should be deliberate, not accidental.
        let oauthSlugs = ProviderCatalog.entries.filter(\.supportsOAuth).map(\.slug)
        #expect(oauthSlugs == ["openrouter"], "OAuth providers changed: \(oauthSlugs)")
    }

    @Test
    func anthropicSkipsModelValidation() {
        // Anthropic doesn't have a cheap key-probe endpoint — explicit
        // .skip avoids spurious "validation failed" errors at save time.
        guard let anthropic = ProviderCatalog.entry(for: "anthropic") else {
            Issue.record("Anthropic entry missing")
            return
        }
        if case .skip = anthropic.validation {
            // expected
        } else {
            Issue.record("Anthropic validation should be .skip; got \(anthropic.validation)")
        }
    }

    @Test
    func openAIBaseURLIsCanonical() {
        let openai = ProviderCatalog.entry(for: "openai")
        #expect(openai?.baseURL.absoluteString == "https://api.openai.com/v1")
    }

    @Test
    func minimaxCoversGlobalAndChinaEndpoints() {
        // MiniMax ships two regional entries: the global OpenAI-compatible
        // endpoint (api.minimax.io) and the China endpoint (api.minimaxi.com).
        // Both must be custom OpenAI-compatible providers with distinct env
        // vars so the host's .env never collides.
        let global = ProviderCatalog.entry(for: "minimax")
        let china = ProviderCatalog.entry(for: "minimax-cn")

        #expect(global != nil, "Global MiniMax entry missing")
        #expect(china != nil, "China MiniMax entry missing")

        #expect(global?.baseURL.absoluteString == "https://api.minimax.io/v1",
                "Global MiniMax base URL mismatch")
        #expect(china?.baseURL.absoluteString == "https://api.minimaxi.com/v1",
                "China MiniMax base URL mismatch")

        #expect(global?.envVar == "MINIMAX_API_KEY")
        #expect(china?.envVar == "MINIMAX_CN_API_KEY")

        #expect(global?.kind == .customProvider(configName: "minimax"))
        #expect(china?.kind == .customProvider(configName: "minimax-cn"))

        if let global {
            #expect(global.tagline.contains("MiniMax-M3"))
            #expect(global.tagline.contains("MiniMax-M3.1-Flash"))
        }
        if let china {
            #expect(china.tagline.contains("MiniMax-M3"))
            #expect(china.tagline.contains("MiniMax-M3.1-Flash"))
        }
    }

    @Test
    func providerModelSummaryDecodesCommonShapes() throws {
        let payloads: [(String, String?)] = [
            (#"{"id":"gpt-5.2","name":"GPT-5.2","context_length":200000}"#, "GPT-5.2"),
            (#"{"id":"glm-4.6","display_name":"GLM 4.6"}"#, "GLM 4.6"),
            (#"{"id":"openai/o5-mini"}"#, nil), // no display name
        ]
        for (raw, expectedName) in payloads {
            let data = Data(raw.utf8)
            let model = try JSONDecoder().decode(ProviderModelSummary.self, from: data)
            #expect(model.displayName == expectedName, "Failed for \(raw)")
        }
    }

    @Test
    func providerModelListResponseDecodes() throws {
        let raw = #"{"data":[{"id":"a"},{"id":"b","name":"Beta"}]}"#
        let payload = try JSONDecoder().decode(ProviderModelListResponse.self, from: Data(raw.utf8))
        #expect(payload.data.map(\.id) == ["a", "b"])
        #expect(payload.data[1].displayName == "Beta")
    }
}
