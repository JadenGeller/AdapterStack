# AdapterStack

Free Abstractions. Explicit Capabilities. Zero Wiring.

Write explicit Swift code. Dependencies are transparent, boundaries are real, and the compiler proves it works.

```swift
// Zero wiring - one struct provides all your dependencies
struct CheckoutServiceProvider: CheckoutServiceAdapterStack {
    let database = PostgreSQL()
    let stripe = StripeGateway() 
    let sendgrid = SendGridClient()
    // Dependencies connect automatically by name
}

// Explicit capabilities - type signatures show exactly what each function can do
func showCheckout<S: CheckoutService>(service: S) {
    // service.database  ❌ Compiler error! 
    // Can only use CheckoutService methods
}

func createOrder<S: OrderService>(service: S) {
    // service.stripe  ❌ Compiler error!
    // Can only use OrderService methods  
}

func sendReceipts<S: NotificationService>(service: S) {
    // service.database  ❌ Compiler error!
    // Can only use NotificationService methods
}

// Free abstractions - boundaries compile to zero-cost direct calls
let provider = CheckoutServiceProvider()
showCheckout(service: provider)      // ✅ Same provider
createOrder(service: provider)       // ✅ Different view
sendReceipts(service: provider)      // ✅ Another view
```

## The Problem

## The Problem

Every Swift app needs to manage dependencies between services. You have three choices, and they all hurt:

### Hidden Dependencies

The convenient path - use singletons everywhere:

```swift
func checkout(cart: Cart) async throws -> Order {
    let user = AuthManager.shared.currentUser
    let items = await InventoryAPI.shared.reserve(cart.items)  
    let payment = try await StripeAPI.shared.charge(cart.total)
    Analytics.shared.track("order_created")
    
    return Order(user: user, items: items, payment: payment)
}
```

This is easy to write but impossible to test, reason about, or refactor. What does `checkout` need? You have to read the entire function body. Want to test with a mock payment provider? Too bad.

### Manual Dependency Passing

The explicit path - pass everything everywhere:

```swift
class CheckoutService {
    private let orderService: OrderService
    private let paymentService: PaymentService
    private let notificationService: NotificationService
    
    init(orderService: OrderService, paymentService: PaymentService, 
         notificationService: NotificationService) {
        self.orderService = orderService
        self.paymentService = paymentService
        self.notificationService = notificationService
    }
}

// But OrderService has its own dependencies...
class OrderService {
    private let cartService: CartService
    private let inventoryService: InventoryService
    private let userService: UserService
    private let database: Database
    
    init(cartService: CartService, inventoryService: InventoryService,
         userService: UserService, database: Database) {
        self.cartService = cartService
        self.inventoryService = inventoryService
        self.userService = userService
        self.database = database
    }
}

// And those services have dependencies too...
// Soon you're writing:
let db = PostgreSQL()
let cartService = CartService(database: db)
let inventoryService = InventoryService(database: db, httpClient: client)
let userService = UserService(database: db, cache: cache)
let orderService = OrderService(
    cartService: cartService,
    inventoryService: inventoryService,
    userService: userService,
    database: db
)
let checkoutService = CheckoutService(
    orderService: orderService,
    paymentService: paymentService,
    notificationService: notificationService
)
// The pain scales with your app
```

Dependencies are explicit and boundaries are real, but the wiring grows without bound. Plus, sharing dependencies requires reference types with heap allocations and reference counting overhead.

### Global Registries

The middle path - service locators or dependency containers:

```swift
container.register(Database.self) { PostgreSQL() }
container.register(PaymentService.self) { StripePayment() }
container.register(OrderService.self) { 
    OrderService(
        database: container.resolve(Database.self)!,
        payment: container.resolve(PaymentService.self)!
    )
}

func checkout(cart: Cart) async throws -> Order {
    let orderService = container.resolve(OrderService.self)!
    let payment = container.resolve(PaymentService.self)!
    // ...
}
```

Less boilerplate, but now you have runtime resolution. Forget to register something? Crash. Typo in your registration? Crash. Want to know what `checkout` needs? Check every `resolve` call. Plus the overhead of runtime lookups instead of direct calls.

## The Solution

AdapterStack gives you free abstractions through Swift's optimizer, explicit capabilities through protocol constraints, and zero wiring through structural sharing:

```swift
// 1. Define what your service does
protocol CheckoutService {
    func checkout(cart: Cart) async throws -> Order
}

// 2. Declare what it needs via protocol composition
@Adapter(CheckoutService.self)  // Generates the CheckoutServiceAdapterStack typealias
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
struct CheckoutServiceProvider: CheckoutServiceAdapterStack {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}
```

No wiring. No boilerplate. Just explicit dependencies and compiler-enforced boundaries.

## How It Works

### Adapters Bridge Protocols to Dependencies

The key insight: separate what a service IS from what it NEEDS.

```swift
// CartService defines WHAT it does
protocol CartService {
    func loadCart() async throws -> Cart
    func saveCart(_ cart: Cart) async throws
}

// CartServiceAdapter declares WHAT IT NEEDS to do that
@Adapter(CartService.self)
protocol CartServiceAdapter: CartService {
    associatedtype DB: Database
    var database: DB { get }
}

// Extension provides HOW using the declared dependencies
extension CartServiceAdapter {
    func loadCart() async throws -> Cart {
        try await database.fetch("cart", as: Cart.self) ?? Cart()
    }
    
    func saveCart(_ cart: Cart) async throws {
        try await database.save("cart", cart)
    }
}
```

Notice the separation: protocol requirements (like `var database: DB`) declare platform primitives - the foundational capabilities your app needs. Protocol composition (like `: CartService, PaymentService`) is how you build higher-level services.

The magic happens through Swift's protocol extensions. When an adapter conforms to multiple protocols, it inherits all their extension methods. This is the key Swift feature that makes the pattern work - protocol extensions provide real implementations, not just signatures. Your adapter gets fully-implemented methods from all its composed protocols and can orchestrate them together.

### Stacks Encapsulate Transitive Dependencies

Stack saves you from declaring transitive dependencies. When CheckoutService needs OrderService, and OrderService needs CartService, you'd normally need to declare all of them:

```swift
// The @Adapter macro on each adapter:
@Adapter(CheckoutService.self)
protocol CheckoutServiceAdapter: CheckoutService, OrderService, PaymentService, NotificationService {}

// Generates this typealias:
extension CheckoutServiceAdapter {
    typealias CheckoutServiceAdapterStack = CheckoutServiceAdapter & OrderServiceAdapterStack & PaymentServiceAdapterStack & NotificationServiceAdapterStack
}

// Without Stack: must declare EVERYTHING (gets worse as dependencies grow)
struct Provider: CheckoutServiceAdapter, OrderServiceAdapter, PaymentServiceAdapter, 
                 NotificationServiceAdapter, CartServiceAdapter, UserServiceAdapter,
                 InventoryServiceAdapter, DatabaseAdapter, PaymentGatewayAdapter, 
                 EmailClientAdapter {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}

// With Stack: just declare what you directly use
struct CheckoutServiceProvider: CheckoutServiceAdapterStack {
    let database = PostgreSQL()
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}
```

Stack gives you local reasoning - you only think about direct dependencies, not the whole tree.

## Core Benefits

### Free Abstractions

Traditional architectures discourage fine-grained services because every boundary requires wiring. This pattern removes both the coding cost AND the runtime cost:

```swift
// Traditional: One big service (boundaries are expensive)
class CheckoutService {
    func loadCart(...) { }
    func calculateTax(...) { }
    func processPayment(...) { }
    func sendNotification(...) { }
    // 20+ mixed responsibilities
}

// This pattern: Many focused services (boundaries are free)
@Adapter(CartService.self)
protocol CartServiceAdapter: CartService, Database {}

@Adapter(TaxService.self)
protocol TaxServiceAdapter: TaxService, LocationService {}

@Adapter(PaymentService.self)
protocol PaymentServiceAdapter: PaymentService, PaymentGateway {}

@Adapter(CheckoutService.self)
protocol CheckoutServiceAdapter: CheckoutService, CartService, TaxService, PaymentService, NotificationService {}
```

When boundaries have no cost, you use them everywhere. Your architecture naturally decomposes into focused, testable units.

The "services" are just protocol methods - no allocations, no vtables, no overhead. Swift's optimizer inlines everything into direct calls, making fine-grained services as fast as monolithic ones.

### Explicit Capabilities

Functions declare their capabilities in their type signature:

```swift
// This function can ONLY do cart operations
func updateCart<S: CartService>(service: S, items: [Item]) async throws

// This function can do cart AND payment operations  
func purchaseCart<S: CartService & PaymentService>(service: S) async throws

// Compare to hidden dependencies:
func purchaseCart() async throws {
    // What can this function do? No way to know without reading the body
    let cart = await CartStorage.shared.load()  // Hidden cart access
    try await StripeAPI.shared.charge(...)      // Hidden payment access
}
```

This is capability-based security at the language level. Functions can only perform the effects you explicitly grant them. Perfect local reasoning about what code can do.

Like effect systems in functional languages, the type signature tells you exactly what effects a function can perform - but using Swift's protocol system rather than specialized syntax.

### Zero Wiring

When multiple services need the same dependency, they share it automatically through structural typing:

```swift
protocol CartServiceAdapter: CartService {
    associatedtype DB: Database
    var database: DB { get }
}

protocol OrderServiceAdapter: OrderService {
    associatedtype DB: Database
    var database: DB { get }  // Same property name!
}

// One property satisfies both
struct CheckoutServiceProvider: CheckoutServiceAdapterStack {
    let database = PostgreSQL()  // Shared by ALL services needing 'database'
    let stripe = StripeGateway()
    let sendgrid = SendGridClient()
}
```

Dependencies propagate automatically by name through structural typing. No manual wiring, no framework, no registry. If two services need the same dependency with the same property name, they share it.

## Why This Works

This pattern achieves something usually impossible: it combines implicit parameter behavior with access control boundaries.

Traditional approaches make you choose:
- **Manual dependency passing** requires objects with lifecycles, retain graphs, and explicit wiring. To share dependencies between services, you need reference types scattered across the heap.
- **Global registries** (service locators, dependency containers) give you convenience but no boundaries - any code can grab any dependency
- **Singletons** are convenient but create hidden dependencies and rigid coupling

AdapterStack uses a single struct (not objects!) that provides everything, but protocols create boundaries. You get automatic wiring, compile-time safety, and value semantics.

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

This is the magic: your provider is a "superservice" with all capabilities, but each use site only sees a narrow slice. The same struct, viewed through different protocol lenses, gives you free abstractions, explicit capabilities, and zero wiring.

## Testing Without Mocks

Mock at your natural service boundaries, not where your architecture forces you. No mocking frameworks, no runtime injection, no fighting your design to write tests. Pick exactly the abstraction level that makes sense for what you're testing.

### Unit Testing

When testing a service in isolation, mock the layer directly below - not the entire tree:

```swift
@Test("Checkout coordinates order creation and payment")
func checkoutOrchestration() async throws {
    struct MockOrderService: OrderService {
        var lastCart: Cart?
        func createOrder(from cart: Cart) async throws -> Order {
            lastCart = cart
            return Order(id: "test-123", total: cart.total)
        }
        // We DON'T need to provide CartService, Database, etc.
        // that OrderService normally requires!
    }
    
    struct MockPaymentService: PaymentService {
        var chargedAmount: Decimal?
        var paymentToken: String?
        func processPayment(for amount: Decimal, token: String) async throws {
            chargedAmount = amount
            paymentToken = token
        }
    }
    
    struct TestCheckout: CheckoutServiceAdapter {
        let orderService = MockOrderService()
        let paymentService = MockPaymentService() 
        let notificationService = MockNotificationService()
    }
    
    let service = TestCheckout()
    let order = try await service.checkout(cart: testCart, token: "tok_test")
    
    #expect(service.orderService.lastCart?.items == testCart.items)
    #expect(service.paymentService.chargedAmount == order.total)
    #expect(service.notificationService.sentEmails.count == 1)
}
```

Notice how we only mock the services CheckoutService directly uses. We don't need to mock Database, Stripe, or any of the deeper dependencies. This keeps tests focused and fast.

### Integration Testing

Sometimes you want confidence that your services work together correctly:

```swift
@Test("Order flows through the full service stack")
func checkoutIntegration() async throws {
    struct TestProvider: CheckoutServiceAdapterStack {
        let database = SQLite(":memory:")      // Real DB, test instance
        let stripe = StripeTestMode()          // Real Stripe, test mode
        let sendgrid = MockEmail()             // Capture emails
    }
    
    let service = TestProvider()
    
    // The real service stack: CheckoutService → OrderService → CartService → Database
    let order = try await service.checkout(cart: testCart, token: "tok_test")
    
    // Verify the order persisted through all layers
    let saved = try await service.loadOrder(id: order.id)
    #expect(saved.items.count == testCart.items.count)
    
    // Verify side effects
    #expect(service.sendgrid.sentEmails.contains { $0.to == order.customerEmail })
}
```

Here we use real implementations of our services with test versions of platform dependencies. This gives us confidence in our service integration without external side effects.

### Scenario Testing

Some scenarios require mixing real and mock services to properly test behavior:

```swift
@Test("Inventory reservation rollback on payment failure")
func inventoryRollback() async throws {
    struct TestProvider: CheckoutServiceAdapterStack {
        let database = PostgreSQL.testDB()        // REAL - need actual transactions
        let stripe = FailAfterNSeconds(2)        // Fails after delay
        let inventory = RealInventoryAPI()       // REAL - testing its rollback logic
        let sendgrid = SpyEmailService()         // Spy - verify notifications
    }
    
    let service = TestProvider()
    let initialStock = try await service.inventory.getStock(itemId: "widget")
    
    await #expect(throws: PaymentError.timeout) {
        try await service.checkout(cart: cartWithWidgets)
    }
    
    // Real database + inventory means we can verify rollback actually worked
    let finalStock = try await service.inventory.getStock(itemId: "widget")
    #expect(finalStock == initialStock)  // Stock was restored
    
    // Spy lets us verify the right notifications went out
    #expect(service.sendgrid.emails.contains { 
        $0.template == "payment-failed" && $0.data["reason"] == "timeout"
    })
}
```

The key insight: mock at the abstraction level that makes sense for what you're testing. Not always at the bottom, not always at the top - exactly where you need.

## SwiftUI Integration

This pattern bridges the gap between SwiftUI's environment and your service layer, letting services access environment values while maintaining boundaries.

### Environment-Based Service Providers

SwiftUI's environment uses structural composition - just like our pattern. Service providers can pull any dependencies from the environment:

```swift
struct CheckoutServiceProvider: CheckoutServiceAdapterStack, DynamicProperty {
    @Environment(\.database) var database
    @Environment(\.stripe) var stripe  
    @Environment(\.sendgrid) var sendgrid
    
    // Can use any property wrapper!
    @State private var retryCount = 0
    @Query(sort: \.timestamp) private var recentOrders: [Order]
    @AppStorage("user_id") private var userId: String?
}

struct CheckoutView: View {
    let cart: Cart
    
    var body: some View {
        CheckoutButton(
            cart: cart,
            service: CheckoutServiceProvider()
        )
    }
}
```

The structural typing works perfectly: SwiftUI provides values by key path, our providers consume them by property name. Same philosophy, seamless integration.

### Previews with Mock Services

Create different service behaviors for SwiftUI previews:

```swift
struct PreviewCheckoutProvider: CheckoutServiceAdapterStack {
    let database = InMemoryDB()
    let stripe: MockStripe
    let sendgrid = MockEmail()
}

#Preview("Successful checkout") {
    CheckoutView(
        cart: .sample,
        service: PreviewCheckoutProvider(stripe: MockStripe(behavior: .success))
    )
}

#Preview("Payment declined") {
    CheckoutView(
        cart: .sample,
        service: PreviewCheckoutProvider(stripe: MockStripe(behavior: .declined))
    )
}

#Preview("Network error") {
    CheckoutView(
        cart: .sample,
        service: PreviewCheckoutProvider(stripe: MockStripe(behavior: .networkError))
    )
}
```

Each preview gets exactly the service behavior it needs to demonstrate that UI state.

### Generic Views with Service Boundaries

Not every view needs a service. Use service-generic views for components that orchestrate business logic:

```swift
// Service view - orchestrates business logic
struct CheckoutButton<Service: CheckoutService>: View {
    let cart: Cart
    let service: Service
    
    @State private var isProcessing = false
    @State private var error: Error?
    
    var body: some View {
        Button("Checkout") {
            Task {
                isProcessing = true
                defer { isProcessing = false }
                
                do {
                    let order = try await service.checkout(cart: cart)
                    // Navigate to success
                } catch {
                    self.error = error
                }
            }
        }
        .disabled(isProcessing)
        .alert("Checkout Failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        }
    }
}

// Data view - just displays data
struct OrderRow: View {
    let order: Order
    
    var body: some View {
        HStack {
            Text(order.id)
            Spacer()
            Text(order.total, format: .currency(code: "USD"))
        }
    }
}

// Container view - composes service and data views
struct CheckoutScreen: View {
    let cart: Cart
    
    var body: some View {
        VStack {
            CartItemsList(items: cart.items)  // Data view
            Divider()
            CartTotalView(total: cart.total)  // Data view
            CheckoutButton(                    // Service view
                cart: cart,
                service: CheckoutServiceProvider()
            )
        }
    }
}
```

Only views that need to perform business operations should be generic over services. Most views just display data.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mattmassicotte/AdapterStack", from: "1.0.1")
]
```

The macro saves one typealias per adapter. The pattern is just protocols.

## License

MIT
