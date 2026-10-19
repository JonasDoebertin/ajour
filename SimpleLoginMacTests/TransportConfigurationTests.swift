import Testing
@testable import SimpleLoginMac

struct TransportConfigurationTests {
    @Test func requestsGiveUpAfter15SecondsWithoutAResponse() {
        #expect(AppModel.sessionConfiguration().timeoutIntervalForRequest == 15)
    }
}
