# RetailApp

An executable iOS MVP based on the system-design notes for a campaign-driven retail home page.

## Dependency graph

```text
RetailAppApp
  -> AppComposition
    -> HomeRepository
      -> HomeAPIClient
      -> HomeCache
    -> AddProductToCart
      -> CartClient
    -> AnalyticsTracker
    -> HomeViewModel
      -> HomeView
        -> typed native section views
```

## Architectural decisions

- The backend controls composition; iOS renders a closed set of typed native sections.
- The demo covers hero, campaign carousel, categories, products, recommendations, editorial, promo, and native fallback sections.
- Unknown or malformed sections are dropped at the DTO boundary without failing valid sections.
- Unsupported and malformed known sections are reported separately through the analytics/observability boundary.
- Invalid items are dropped independently and recorded with section/item identity.
- `HomeRepository` is concrete and owns meaningful API/cache/freshness policy.
- `AddProductToCart` is a use case because it owns availability validation and mutation reconciliation.
- No repository protocols, service locator, pass-through data sources, or one-use-case-per-method hierarchy.
- `AppComposition` owns application-scoped dependencies; `HomeViewModel` owns screen state.
- Cached and fresh values are represented explicitly through `AsyncThrowingStream<HomeUpdate, Error>`.
- SwiftUI `.task` and `.refreshable` structurally own Home loading and cancellation.
- Cart summaries carry a monotonic revision so stale concurrent responses cannot overwrite newer state.
- Add-to-cart updates the badge immediately, shows a pending `Added` state, rolls back on failure, and reconciles with the latest canonical server summary.
- Demo cart retries are idempotent even across actor reentrancy, and screen-owned mutation tasks are cancelled on teardown.
- Impressions are emitted from item visibility with a 50% threshold rather than section construction.
- Search suggestions use a concrete client with debounce, replacement cancellation, and navigation into the search boundary.
- Unknown sections may supply a constrained fallback banner; arbitrary backend layout remains unsupported.
- Remote images use an app-scoped pipeline with target-size downsampling, bounded memory cache, in-flight request deduplication, and view-task cancellation.
- Full-screen failure, refresh failure and cart mutation state have different UI blast radii.

`HomeAPIClient.demo()` and `CartClient.demo()` make the project runnable without a backend. Replace their closures in `AppComposition` to connect live endpoints.
