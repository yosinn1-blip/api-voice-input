import Testing
@testable import APIVoiceInputCore

@Suite("GroqAPIKeySetup")
struct GroqAPIKeySetupTests {
    @Test("opens the Groq API key management page")
    func apiKeyURL() throws {
        #expect(GroqAPIKeySetup.apiKeyURL.absoluteString == "https://console.groq.com/keys")
    }

    @Test("normalizes pasted keys without keeping surrounding whitespace or quotes")
    func normalizedPastedKey() {
        #expect(GroqAPIKeySetup.normalizedAPIKey("  \"gsk_example\"  ") == "gsk_example")
        #expect(GroqAPIKeySetup.normalizedAPIKey("\n'gsk_example'\n") == "gsk_example")
    }

    @Test("rejects empty pasted keys")
    func rejectsEmptyKeys() {
        #expect(GroqAPIKeySetup.normalizedAPIKey("  \"\"  ") == nil)
    }

    @Test("shows onboarding only when key is missing and prompt has not been dismissed")
    func onboardingPromptDecision() {
        #expect(GroqAPIKeySetup.shouldShowOnboarding(hasAPIKey: false, dismissed: false))
        #expect(GroqAPIKeySetup.shouldShowOnboarding(hasAPIKey: true, dismissed: false) == false)
        #expect(GroqAPIKeySetup.shouldShowOnboarding(hasAPIKey: false, dismissed: true) == false)
    }

    @Test("does not read Keychain secret when a secrets file key is already available")
    func avoidsKeychainReadWhenSecretsFileHasKey() {
        #expect(GroqAPIKeySetup.shouldReadKeychainSecret(secretsFileKey: "gsk_existing") == false)
        #expect(GroqAPIKeySetup.shouldReadKeychainSecret(secretsFileKey: nil))
        #expect(GroqAPIKeySetup.shouldReadKeychainSecret(secretsFileKey: ""))
    }
}
