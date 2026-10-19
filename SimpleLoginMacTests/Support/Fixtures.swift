import Foundation
import SimpleLoginKit

enum Fixtures {
    static let userInfoJSON = #"{"name":"Jonas","email":"jonas@example.com","is_premium":true,"in_trial":false,"profile_picture_url":null,"max_alias_free_plan":10}"#
    static let userInfo = UserInfo(name: "Jonas", email: "jonas@example.com", isPremium: true)

    static func aliasJSON(id: Int, email: String = "shop@example.com", enabled: Bool = true, forwardedAt: Date? = nil) -> String {
        let latestActivity = forwardedAt.map {
            #"{"action":"forward","timestamp":\#(Int($0.timeIntervalSince1970)),"contact":{"email":"login@shop.com","name":null,"reverse_alias":"x"}}"#
        } ?? "null"
        return #"""
        {"id":\#(id),"email":"\#(email)","name":null,"enabled":\#(enabled),"note":null,"pinned":true,"nb_block":0,"nb_forward":0,"nb_reply":0,
         "creation_timestamp":1586195834,"mailbox":{"id":1,"email":"a@b.c"},"mailboxes":[{"id":1,"email":"a@b.c"}],
         "latest_activity":\#(latestActivity)}
        """#
    }

    static func aliasPageJSON(ids: some Sequence<Int>) -> String {
        #"{"aliases":[\#(ids.map { aliasJSON(id: $0, email: "alias\($0)@example.com") }.joined(separator: ","))]}"#
    }

    static func toggleJSON(enabled: Bool) -> String {
        #"{"enabled":\#(enabled)}"#
    }
}
