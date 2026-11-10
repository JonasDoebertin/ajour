import Testing
@testable import Ajour

struct AboutTextTests {
    @Test func versionShowsTheVersionAndTheBuild() {
        #expect(AboutText.version(info: ["CFBundleShortVersionString": "0.4.3", "CFBundleVersion": "17"]) == "Version 0.4.3 (17)")
    }

    @Test func versionWithoutABuildShowsOnlyTheVersion() {
        #expect(AboutText.version(info: ["CFBundleShortVersionString": "0.4.3"]) == "Version 0.4.3")
    }

    @Test func noVersionWithoutAVersionString() {
        #expect(AboutText.version(info: ["CFBundleVersion": "17"]) == nil)
    }
}
