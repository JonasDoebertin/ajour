import SwiftUI

struct StateSymbolView: View {
    let kind: AliasStatus.Kind

    var body: some View {
        Image(nsImage: StateSymbol.image(for: kind, highlighted: false))
    }
}
