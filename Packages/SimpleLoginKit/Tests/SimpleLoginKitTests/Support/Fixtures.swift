import Foundation
@testable import SimpleLoginKit

enum Fixtures {
    static let aliasJSON = #"""
    {"id":7,"email":"shop@example.com","name":null,"enabled":true,"note":null,"pinned":true,"nb_block":3,"nb_forward":1,"nb_reply":0,
     "creation_timestamp":1586195834,"support_pgp":false,"disable_pgp":false,
     "mailbox":{"id":1,"email":"a@b.c"},"mailboxes":[{"id":1,"email":"a@b.c"}],
     "latest_activity":{"action":"forward","timestamp":1586195834,"contact":{"email":"login@shop.com","name":null,"reverse_alias":"x"}}}
    """#

    static let mailboxesJSON = #"""
    {"mailboxes":[
      {"email":"a@b.c","id":1,"default":true,"creation_timestamp":1590918512,"nb_alias":10,"verified":true},
      {"email":"m1@example.com","id":2,"default":false,"creation_timestamp":1590918512,"nb_alias":0,"verified":true}]}
    """#
}

extension Alias {
    static func fixture(
        id: Int = 1,
        email: String = "shop@example.com",
        enabled: Bool = false,
        pinned: Bool = true,
        latestActivity: AliasActivity? = nil
    ) -> Alias {
        Alias(
            id: id,
            email: email,
            name: nil,
            enabled: enabled,
            note: nil,
            pinned: pinned,
            nbBlock: 0,
            nbForward: 0,
            latestActivity: latestActivity,
            mailboxes: [MailboxRef(id: 1, email: "a@b.c")]
        )
    }
}
