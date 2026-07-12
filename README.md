# RetailApp

An executable iOS companion project for a [system design discussion](https://www.youtube.com/watch?v=gw53PnF5pNQ) about a dynamic, campaign-driven retail home page.

The project shows how several ideas from an iOS system design interview can be translated into working Swift code:

* server-driven composition with typed native sections;
* defensive DTO mapping;
* cache-first home loading;
* optimistic add-to-cart with server reconciliation;
* visibility-based analytics;
* cancellable search suggestions;
* target-size image downsampling and request deduplication.

This is an educational MVP, not a production-ready commerce application or a universal architecture template.

---

## Demo

<img width="287" height="593" alt="Image" src="https://github.com/user-attachments/assets/2150503e-adb3-4eef-b37d-e63eb5398f5a" />

The app runs with local demo clients, so no backend configuration is required.

---

## Project goals

The sample focuses on the iOS client architecture for a dynamic retail home page.

The backend controls the commercial composition:

* which sections appear;
* section order;
* content;
* tracking metadata;
* compatibility and fallback information.

The iOS app owns:

* native rendering;
* screen state;
* navigation;
* caching policy;
* image loading;
* analytics dispatch;
* failure handling.

The central design choice is:

> Server-driven composition, not full server-driven UI.

The backend can compose a known set of native sections, but it cannot describe arbitrary layouts, gestures, animations, or view hierarchies.

---

## What the project demonstrates

### Typed native sections

The home page supports a closed set of section types:

* hero campaign;
* campaign carousel;
* categories;
* products;
* recommendations;
* editorial content;
* promotions;
* constrained fallback banners.

Unknown or malformed sections are handled at the DTO boundary without failing valid sections.

Invalid items can be dropped independently while the rest of the section remains usable.

For this MVP, section rendering is implemented with an exhaustive Swift `switch`. In a larger codebase, the same mapping could be extracted into renderer factories or feature modules.

---

### Defensive DTO mapping

Raw API DTOs do not flow directly into the UI.

The mapping layer:

* validates required fields;
* maps known section types into domain models;
* drops invalid items where possible;
* isolates malformed sections;
* reports contract problems through the analytics and observability boundary;
* supports a constrained native fallback for selected unknown sections.

The UI receives models it can render safely.

---

### Cache-first home loading

`HomeRepository` owns the policy for loading and refreshing the home page.

It can:

1. return cached content quickly;
2. decide whether the cached value is still fresh;
3. request an updated value from the API;
4. map the response into domain models;
5. persist the result back to cache.

Cached and fresh values are represented explicitly through:

```swift
AsyncThrowingStream<HomeUpdate, Error>
```

This allows the screen to render cached content first and update when the fresh response arrives.

The repository is intentionally concrete. It owns meaningful API, cache, freshness, and refresh policy rather than acting as a pass-through abstraction.

---

### Single-flight refresh

Concurrent refresh requests share the same in-flight operation.

This prevents duplicate API calls when several parts of the screen request the same refresh at nearly the same time.

---

### Optimistic add-to-cart

Add-to-cart updates the UI immediately, while the server response remains the source of truth.

The flow is:

```text
User action
    -> optimistic cart update
    -> send mutation
    -> validate server response
    -> reconcile or roll back
```

The implementation includes:

* immediate badge updates;
* a pending `Added` state;
* rollback on failure;
* availability validation;
* monotonic cart revisions;
* protection against stale concurrent responses;
* idempotent retry behavior;
* cancellation of screen-owned mutation tasks on teardown.

The home page treats price and availability as display snapshots. The cart mutation validates the canonical state.

---

### Visibility-based analytics

Impressions are not emitted when an item is decoded or inserted into the view hierarchy.

An impression is emitted only when the item crosses a visibility threshold.

The sample uses a 50% threshold and keeps impression tracking separate from section construction.

Analytics and observability also report:

* unsupported sections;
* malformed known sections;
* invalid items;
* section and item identity;
* navigation and cart interactions.

The concrete analytics provider remains outside the Home screen.

---

### Search suggestions

Search suggestions use:

* input debounce;
* replacement cancellation;
* concrete client injection;
* navigation into the search boundary.

The project intentionally does not implement full search ranking, filters, typo tolerance, or a complete search results system.

---

### Image pipeline

Remote images are loaded through an application-scoped `ImagePipeline`.

The pipeline handles:

* cache keys based on URL and target size;
* target-size downsampling;
* bounded memory caching;
* in-flight request deduplication;
* cancellation through SwiftUI view task lifetime;
* protection against decoding unnecessarily large bitmaps.

The sample intentionally does not implement a custom persistent disk cache.

A production application would normally evaluate a mature library such as Nuke, Kingfisher, or SDWebImage, or add a dedicated disk-cache layer when required.

The architecture remains the same regardless of the concrete implementation:

```text
View
    -> ImagePipeline
    -> Memory cache
    -> Network / CDN
    -> Downsample
    -> Render
```

---

### Failure boundaries

Different failures have different UI blast radii.

```text
Initial home failure
    -> full-screen error or retry

Refresh failure
    -> keep existing content
    -> show lightweight refresh error

Invalid section
    -> drop or replace that section

Invalid item
    -> drop that item

Image failure
    -> show placeholder

Cart mutation failure
    -> roll back optimistic state

Analytics failure
    -> do not block the UI
```

One broken section should not become a broken home page.

---

## UI framework note

The system design discussion considered UIKit a strong option for a large, performance-sensitive production feed.

This companion project uses SwiftUI to keep the implementation compact and easier to explore.

The core design is UI-framework independent:

* typed section models;
* defensive DTO mapping;
* repository policy;
* cache-first loading;
* navigation boundaries;
* cart reconciliation;
* analytics;
* image pipeline.

The same domain and data layers could support a `UICollectionView` implementation using compositional layout, diffable data source, and prefetching.

SwiftUI view lifetime owns asynchronous work through APIs such as:

```swift
.task
.refreshable
```

This gives the sample structured cancellation without introducing a separate task-management framework.

---

## Architecture

```text
RetailAppApp
    |
    v
AppComposition
    |
    +--> HomeRepository
    |       |
    |       +--> HomeAPIClient
    |       +--> HomeCache
    |
    +--> AddProductToCart
    |       |
    |       +--> CartClient
    |
    +--> AnalyticsTracker
    |
    +--> ImagePipeline
    |
    v
HomeViewModel
    |
    v
HomeView
    |
    v
Typed native section views
```

### Presentation

Responsible for:

* screen state;
* rendering;
* user actions;
* search input;
* item visibility;
* navigation events.

Main types include:

* `HomeView`
* `HomeViewModel`
* section views
* navigation destinations

### Application

Contains operations that coordinate business behavior.

Examples:

* loading the home page;
* refreshing content;
* add-to-cart reconciliation;
* tracking events.

A use case is introduced only when it owns meaningful policy. The project intentionally avoids a one-use-case-per-method hierarchy.

### Domain

Contains models used by the application and presentation layers.

The main model hierarchy is:

```text
HomePage
    -> HomeSection
        -> HomeItem
            -> Destination
```

Domain models do not depend on API DTOs or SwiftUI views.

### Data

Owns:

* API clients;
* DTOs;
* mapping;
* cache persistence;
* repository policy.

The DTO boundary protects the rest of the app from unsupported or malformed backend content.

### Infrastructure

Contains shared application-level concerns such as:

* image loading;
* analytics;
* caching utilities;
* demo infrastructure.

### Composition root

`AppComposition` creates and connects application-scoped dependencies.

The project intentionally does not use:

* a service locator;
* global mutable dependency containers;
* repository protocols without multiple meaningful implementations;
* pass-through data sources;
* unnecessary abstractions around every method.

---

## Main data flow

### Initial home loading

```text
HomeView
    -> HomeViewModel
    -> HomeRepository
    -> HomeCache
    -> emit cached value if available
    -> HomeAPIClient
    -> DTO mapping
    -> emit fresh value
    -> update UI
```

### Section rendering

```text
HomeSection
    -> exhaustive typed mapping
    -> native SwiftUI section view
```

### Navigation

```text
User tap
    -> section action
    -> Destination
    -> navigation boundary
```

### Add-to-cart

```text
User tap
    -> optimistic UI update
    -> AddProductToCart
    -> CartClient
    -> canonical CartSummary
    -> reconcile or roll back
```

### Analytics

```text
Visible item
    -> visibility threshold
    -> AnalyticsTracker
    -> analytics boundary
```

### Images

```text
Section view
    -> ImagePipeline
    -> memory cache
    -> in-flight request lookup
    -> network
    -> downsample
    -> display
```

---

## Project structure

```text
RetailApp
├── App
│   └── AppComposition.swift
├── Application
│   └── Application operations and policies
├── Data
│   ├── API clients
│   ├── DTOs
│   ├── mapping
│   ├── cache
│   └── HomeRepository
├── Domain
│   └── Home, cart, navigation, and tracking models
├── Infrastructure
│   ├── ImagePipeline.swift
│   └── shared infrastructure
├── Presentation
│   ├── HomeView.swift
│   ├── HomeViewModel.swift
│   └── native section views
└── RetailAppApp.swift

RetailAppTests
└── SystemDesignTests.swift
```

---

## Running the project

### Requirements

* macOS with a compatible version of Xcode
* iOS 26.0 SDK or newer
* iOS 26.0 deployment target
* no external backend
* no third-party package dependencies

### Steps

1. Clone the repository:

```bash
git clone https://github.com/Livsy90/RetailApp.git
```

2. Open the Xcode project:

```bash
open RetailApp/RetailApp.xcodeproj
```

3. Select the `RetailApp` scheme.

4. Choose an iPhone simulator.

5. Build and run the project.

The application uses:

```swift
HomeAPIClient.demo()
CartClient.demo()
```

These demo clients make the project runnable without server configuration.

---

## Connecting a real backend

Replace the demo client closures in `AppComposition`.

The Home client should provide a response that can be mapped into the supported section DTOs.

The Cart client should return a canonical cart summary with a monotonic revision.

Keep these responsibilities separate:

```text
Home API
- composition
- sections
- items
- tracking
- compatibility
- freshness

Cart API
- mutation validation
- canonical item count
- price and availability validation
- monotonic revision

Analytics API
- impressions
- taps
- search interactions
- cart interactions
- contract issues
```

Do not pass networking responses directly into the views. Keep DTO mapping at the data boundary.

---

## Tests

The test target includes scenarios around the most important system design decisions.

Examples include:

* cached home freshness;
* cache context separation;
* persisted cache behavior;
* single-flight refresh;
* malformed and unsupported sections;
* constrained fallback behavior;
* stale cart response protection;
* lost cart response and idempotent retry.

Run the tests from Xcode with:

```text
Product -> Test
```

Or from the command line with an available simulator:

```bash
xcodebuild test \
  -project RetailApp.xcodeproj \
  -scheme RetailApp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Adjust the simulator name to one installed on your machine.

---

## Deliberate limitations

This project is intentionally small.

It does not attempt to implement:

* a full server-driven UI engine;
* arbitrary backend-provided layouts;
* a production CMS;
* recommendation ranking;
* authentication;
* checkout or payment;
* full cart management;
* complete product details;
* full search results;
* home-level infinite scrolling;
* a persistent custom image disk cache;
* production analytics delivery;
* offline-first synchronization;
* compile-time module boundaries;
* a reusable commerce framework.

Home-level pagination is represented in the contract but is intentionally not a central part of the demo.

The initial home response is expected to contain enough sections and items to render meaningful content. A production system could add optional home-level or section-level cursors when the product requires a longer discovery feed.

---

## Why some abstractions are missing

The sample avoids abstractions that do not yet own meaningful policy.

For example:

* `HomeRepository` is concrete because there is one implementation with real cache and refresh behavior.
* Section rendering uses an exhaustive `switch` because the number of supported types is still small.
* API clients are concrete values with injected closures rather than protocol hierarchies.
* The project uses logical folders instead of separate Swift modules.

These choices keep the sample readable.

A larger application could extract:

* section renderers into feature modules;
* API and domain layers into separate packages;
* a dedicated navigation system;
* persistent image caching;
* production analytics batching;
* feature-specific composition roots.

Those changes should follow real scaling pressure, not be added by default.

---

## Key design principles

```text
Start with scope, not architecture.

Model the home page as a composition of sections,
not as a flat product list.

Let the backend control what appears.

Let iOS control how supported content is rendered.

Validate external data at the boundary.

Keep failures local.

Treat image loading as shared infrastructure.

Track impressions from actual visibility.

Use optimistic UI only with reconciliation.

Prefer concrete dependencies until an abstraction earns its cost.

Measure performance instead of assuming it.
```

---

## Companion material

This repository was created as a companion implementation for an iOS system design discussion about a campaign-driven retail home page.

[Watch the full system design episode](https://www.youtube.com/watch?v=gw53PnF5pNQ)

The discussion covers:

* scope clarification;
* functional and non-functional requirements;
* data modeling;
* Home Composition API design;
* high-level iOS architecture;
* server-driven composition and compatibility;
* image loading, caching, and scrolling performance.

---

## Disclaimer

This repository presents one possible implementation of the discussed design.

It is not the only valid architecture, and it should not be copied into a production application without considering:

* team structure;
* deployment targets;
* existing infrastructure;
* performance measurements;
* backend capabilities;
* product requirements;
* release and migration constraints.

Use the project as a concrete example of architectural reasoning, not as a universal template.

---

## Contributing

Issues and pull requests are welcome.

Please keep contributions aligned with the educational scope of the project. Large framework abstractions or unrelated commerce features should be discussed in an issue before implementation.
