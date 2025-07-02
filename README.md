# AdapterStack

Write honest Swift code. Dependencies are explicit, boundaries are real, and the compiler proves it works.

```swift
// One struct provides all your dependencies
struct CheckoutServiceProvider: CheckoutServiceAdapter.Stack {
    let database = PostgreSQL()
    let stripe = StripeGateway() 
    let sendgrid = SendGridClient()
}

// Pass it everywhere - each use site only sees what it needs
func showCheckout<S: CheckoutService>(service: S) {
    // service.database  ❌ Compiler error! 
    // Can only use CheckoutService methods
}

func processPayment<S: PaymentService>(service: S) {
    // service.sendgrid  ❌ Compiler error!
    // Can only use PaymentService methods  
}

let provider = CheckoutServiceProvider()
showCheckout(service: provider)      // ✅ Same provider
processPayment(service: provider)    // ✅ Different view
```

## The Problem

Most Swift code lies about its dependencies. Functions secretly reach into singletons and services know too much about each other:

```swift
// Dishonest code - what does this really need?
func createOrder() async throws -> Order {
    let user = AuthManager.shared.currentUser  // Hidden dependency
    let cart = await CartStorage.shared.load() // Another one
    let payment = try await StripeAPI.charge() // And another
    Analytics.track("order_created")            // Effects everywhere
    
    return Order(user: user, cart: cart)
}
```

The cost compounds: hidden dependencies make testing painful, reasoning impossible, and refactoring dangerous.

## The Solution

AdapterStack makes dependencies explicit through Swift's type system. Services declare exactly what they need:

```swift
// 1. Define what your service does
protocol CheckoutService {
    func checkout(cart: Cart) async throws -> Order
}

// 2. Declare what it needs via protocol composition
@Adapter(CheckoutService.self)  // Generates the .Stack typealias
protocol CheckoutServiceAdapter: CheckoutService, OrderService, PaymentService, NotificationService {}

// 3. Implement by composing other services
extension CheckoutServiceAdapter {
    func checkout(cart: Cart) async throws -> Order {
        let order = try await createOrder(from: cart)        // From OrderService
        try await processPayment(for: order.total)           // From PaymentService
        try await sendOrderConfirmation(for: order)          // From NotificationService
        return order
    }
}

// 4. Create one struct with your dependencies
struct CheckoutServiceProvider: CheckoutServiceAdapter.Stack {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}
```

Now dependencies are explicit, boundaries are enforced, and everything is testable.

## How It Works

### Adapters Bridge Protocols to Dependencies

The key insight: separate what a service IS from what it NEEDS.

```swift
// CheckoutService defines the interface
protocol CheckoutService {
    func checkout() async throws -> Order
}

// CheckoutServiceAdapter declares dependencies
@Adapter(CheckoutService.self)
protocol CheckoutServiceAdapter: CheckoutService, OrderService, PaymentService, NotificationService {}

// How do adapters provide functionality? Through protocol extensions:
extension CheckoutServiceAdapter {
    func checkout() async throws -> Order {
        // Since this type conforms to OrderService, PaymentService & NotificationService,
        // we can use their methods directly:
        let order = try await createOrder()                 // From OrderService protocol
        try await processPayment(order.total)               // From PaymentService protocol
        try await sendOrderConfirmation(for: order)         // From NotificationService protocol
        return order
    }
}
```

The adapter just uses the methods from its composed protocols - it doesn't care how they're implemented.

### Stacks Encapsulate Transitive Dependencies

Stack saves you from declaring transitive dependencies. Instead of listing every adapter in the dependency tree, you just declare what you directly need:

```swift
// Without Stack: must declare entire dependency tree
struct Provider: CheckoutServiceAdapter, OrderServiceAdapter, PaymentServiceAdapter, NotificationServiceAdapter {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}

// With Stack: only think about direct dependencies
struct CheckoutServiceProvider: CheckoutServiceAdapter.Stack {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}

// The macro generates this typealias per adapter:
extension CheckoutServiceAdapter {
    typealias Stack = Self & OrderServiceAdapter.Stack & PaymentServiceAdapter.Stack & NotificationServiceAdapter.Stack
}
```

Stack gives you local reasoning - you only think about direct dependencies, not the whole tree.

### The Key Insight

What makes this pattern special is how it reconciles two seemingly incompatible goals.

This pattern cleverly combines two things that normally conflict:

**1. Implicit parameter behavior** - Dependencies flow automatically through structural typing  
**2. Access control boundaries** - Protocol constraints limit what each function can access

Traditional approaches make you choose:
- Classes with `private` give you boundaries but require manual wiring, boilerplate, and deep hierarchies
- Service locators give you convenience but no boundaries

AdapterStack puts all methods in the same namespace (your provider struct) but uses protocols to control access. You get both automatic wiring AND compile-time boundaries.

```swift
struct Provider: CheckoutServiceStack {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    
    // Has ALL methods from ALL services
    // But protocol constraints control access!
}

func processPayment<S: PaymentService>(service: S) {
    // Can only see PaymentService methods
    // Even though 'service' has everything
}
```

This is the magic: your provider is a "superservice" with all capabilities, but each use site only sees a narrow slice. The same struct, viewed through different protocol lenses.

## Core Benefits

This design gives you four powerful properties that are usually at odds with each other:

### Dependencies Are Explicit (Capability Security)

Functions declare their capabilities in their type signature:

```swift
// This function can ONLY do payment operations
func charge<S: PaymentService>(service: S, amount: Decimal) async throws

// This function can do payments AND notifications  
func chargeAndNotify<S: PaymentService & NotificationService>(service: S) async throws

// Compare to traditional code where capabilities are hidden:
func charge(amount: Decimal) async throws {
    // What can this function do? No way to know without reading the body
}
```

This is capability-based security at the language level. Functions can only perform the effects you explicitly grant them. Perfect local reasoning about what code can do.

### Boundaries Are Compiler-Enforced

Traditional architectures rely on convention or documentation for boundaries. This pattern makes them real:

```swift
func handlePayment<S: PaymentService>(service: S, amount: Decimal) async throws {
    try await service.charge(amount: amount)
    // service.database.query(...)  ❌ Compiler error - no database access here!
}

func handleOrder<S: OrderService & PaymentService>(service: S) async throws {
    let order = try await service.createOrder()
    try await service.charge(amount: order.total)  // ✅ Can access payment methods
}
```

The compiler proves your architectural boundaries. Not by convention, not by documentation - by the type system.

### Dependencies Shared Structurally (Implicit Parameters)

When multiple services need the same dependency, they share it automatically:

```swift
protocol OrderServiceAdapter: OrderService {
    associatedtype DB: Database
    var database: DB { get }
}

protocol NotificationServiceAdapter: NotificationService {
    associatedtype DB: Database
    var database: DB { get }  // Same property name!
}

// One property satisfies both
struct AppServiceProvider: AppServiceStack {
    let database = PostgreSQL()  // Shared by ALL services needing 'database'
}
```

Like implicit parameters in Scala/Haskell, dependencies propagate automatically by name through structural typing.

### Zero Runtime Cost

The pattern compiles away entirely:
- **Static dispatch**: Protocol requirements become direct calls via generics
- **Value semantics**: Providers are structs - no allocations, no reference counting
- **Cross-module inlining**: Swift inlines protocol methods across module boundaries
- **No intermediates**: No service locator, no container, no runtime resolution

## Testing Without Mocks

No mocking frameworks needed. Just different implementations:

```swift
// Production
struct ProdCheckoutServiceProvider: CheckoutServiceAdapter.Stack {
    let database = PostgreSQL()
    let stripe = StripeAPI()
    let sendgrid = SendGridClient()
}

// Testing  
struct TestCheckoutServiceProvider: CheckoutServiceAdapter.Stack {
    let database = InMemoryDB()
    let stripe = MockStripe()
    let sendgrid = MockSendGrid()
}

// Use the same functions with different providers
func test() async {
    let prod = ProdCheckoutServiceProvider()
    let test = TestCheckoutServiceProvider()
    
    // Same interface, different behavior
    try await handleCheckout(service: prod, cart: cart)  // Hits real Stripe
    try await handleCheckout(service: test, cart: cart)  // Uses mock
}
```

## SwiftUI Integration

Services can bridge to SwiftUI's environment:

```swift
struct CheckoutServiceProvider: CheckoutServiceAdapter.Stack, DynamicProperty {
    @Environment(\.database) var database
    @Environment(\.stripe) var stripe
    @Environment(\.sendgrid) var sendgrid
}

struct CheckoutView: View {
    let cart: Cart
    
    var body: some View {
        CheckoutButton(
            cart: cart,
            service: CheckoutServiceProvider()  // Pulls from environment
        )
    }
}
```

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mattmassicotte/AdapterStack", from: "1.0.0")
]
```

The macro saves one typealias per adapter. The pattern is just protocols.

## License

MIT
