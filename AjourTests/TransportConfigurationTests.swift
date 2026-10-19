import Testing
@testable import Ajour

struct TransportConfigurationTests {
    @Test func requestsGiveUpAfter15SecondsWithoutAResponse() {
        #expect(AppModel.sessionConfiguration().timeoutIntervalForRequest == 15)
    }
}
