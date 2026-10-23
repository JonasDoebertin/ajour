import Foundation
import SimpleLoginKit

enum Fixtures {
    static let userInfoJSON = #"{"name":"Jonas","email":"jonas@example.com","is_premium":true,"in_trial":false,"profile_picture_url":null,"max_alias_free_plan":10}"#
    static let userInfo = UserInfo(name: "Jonas", email: "jonas@example.com", isPremium: true)

    static func aliasJSON(id: Int, email: String = "shop@example.com", enabled: Bool = true, pinned: Bool = true, note: String? = nil, forwardedAt: Date? = nil) -> String {
        let latestActivity = forwardedAt.map {
            #"{"action":"forward","timestamp":\#(Int($0.timeIntervalSince1970)),"contact":{"email":"login@shop.com","name":null,"reverse_alias":"x"}}"#
        } ?? "null"
        return #"""
        {"id":\#(id),"email":"\#(email)","name":null,"enabled":\#(enabled),"note":\#(note.map { "\"\($0)\"" } ?? "null"),"pinned":\#(pinned),"nb_block":0,"nb_forward":0,"nb_reply":0,
         "creation_timestamp":1586195834,"mailbox":{"id":1,"email":"a@b.c"},"mailboxes":[{"id":1,"email":"a@b.c"}],
         "latest_activity":\#(latestActivity)}
        """#
    }

    static func aliasPageJSON(ids: some Sequence<Int>) -> String {
        #"{"aliases":[\#(ids.map { aliasJSON(id: $0, email: "alias\($0)@example.com") }.joined(separator: ","))]}"#
    }

    static func alias(id: Int, email: String = "shop@example.com", enabled: Bool = true, pinned: Bool = false, note: String? = nil) -> Alias {
        Alias(id: id, email: email, name: nil, enabled: enabled, note: note, pinned: pinned, nbBlock: 0, nbForward: 0, latestActivity: nil, mailboxes: [])
    }

    static func toggleJSON(enabled: Bool) -> String {
        #"{"enabled":\#(enabled)}"#
    }

    static func newAliasJSON(id: Int, email: String) -> String {
        aliasJSON(id: id, email: email, pinned: false)
    }

    static func suffixJSON(_ suffix: String, isCustom: Bool) -> String {
        #"{"suffix":"\#(suffix)","signed_suffix":"\#(suffix).signed","is_custom":\#(isCustom),"is_premium":false}"#
    }

    static func aliasOptionsJSON(canCreate: Bool = true, suffixes: [String]) -> String {
        #"{"can_create":\#(canCreate),"prefix_suggestion":"","suffixes":[\#(suffixes.joined(separator: ","))]}"#
    }

    static func mailboxJSON(id: Int, email: String, isDefault: Bool) -> String {
        #"{"id":\#(id),"email":"\#(email)","default":\#(isDefault),"creation_timestamp":1590918512,"nb_alias":0,"verified":true}"#
    }

    static func mailboxesJSON(_ mailboxes: [String]) -> String {
        #"{"mailboxes":[\#(mailboxes.joined(separator: ","))]}"#
    }
}
