import Foundation

public extension APM {
    /// Records a navigation breadcrumb for a screen view (MOB-12's screen-transition signal).
    /// **Host-invoked, not automatic** — see `AutomaticBreadcrumbSource`'s doc comment for
    /// why this SDK doesn't swizzle `viewDidAppear` to do this for free. `name` is
    /// developer-supplied free text and flows through the same `Scrubber` as every other
    /// string once it's attached to an error/crash event — no special handling needed here.
    static func recordScreen(_ name: String) {
        breadcrumb(name, category: .navigation)
    }
}

#if os(iOS)
import UIKit

/// Opt-in: subclass this instead of `UIViewController` to get a screen breadcrumb on every
/// appearance, defaulting to the type name so the common case is one line — just the
/// subclass, no override required.
open class APMTrackedViewController: UIViewController {
    open var apmScreenName: String { String(describing: type(of: self)) }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        APM.recordScreen(apmScreenName)
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Opt-in SwiftUI screen tracking — records a navigation breadcrumb when this view
    /// appears. `.apmScreen("Checkout")` on the screen's root view.
    func apmScreen(_ name: String) -> some View {
        onAppear { APM.recordScreen(name) }
    }
}
#endif
