# AdapterStack

A Swift macro for protocol-based dependency injection that eliminates boilerplate while maintaining type safety.

## Quick Start

```swift
import AdapterStack

// 1. Define your service protocols
protocol OrderService {
    func createOrder() async throws -> Order
}

// 2. Create adapters with the @Adapter macro
@Adapter(OrderService.self)
protocol OrderServiceAdapter: OrderService, CartStorage, PaymentService {
    // Macro generates: typealias Stack = Self & CartStorage.Stack & PaymentService.Stack
}

// 3. Implement your business logic
extension OrderServiceAdapter {
    func createOrder() async throws -> Order {
        let cart = try await loadCart()           // From CartStorage
        let payment = try await processPayment()  // From PaymentService
        return Order(cart: cart, payment: payment)
    }
}

// 4. Create environment with just platform dependencies
struct Environment: OrderServiceAdapter.Stack {
    let database = SQLiteDatabase()
    let paymentGateway = StripeGateway()
}

// 5. Use through protocols
let env = Environment()
let order = try await env.createOrder()  // Type-safe, no wiring
```

## The Problem

Traditional dependency injection requires manually building object graphs:

```swift
// Manual wiring becomes complex quickly
let db = Database()
let payment = PaymentGateway()
let cartStorage = CartStorageImpl(database: db)
let paymentService = PaymentServiceImpl(gateway: payment)
let orderService = OrderServiceImpl(cart: cartStorage, payment: paymentService)
```

## The Solution

AdapterStack uses Swift's protocol system to eliminate wiring:

- **Protocols define capabilities** (what services can do)
- **Adapters compose protocols** (how services depend on each other)  
- **Environments provide implementations** (platform dependencies only)
- **The macro generates Stack typealiases** (dependency composition automation)

## Core Concepts

### Adapters
Protocols that define service capabilities and their dependencies:

```swift
@Adapter(CartStorage.self)
protocol CartStorageAdapter: CartStorage {
    var database: Database { get }  // Declares dependency
}

extension CartStorageAdapter {
    func saveCart(_ cart: Cart) async throws {
        // Implementation using database dependency
    }
}
```

### Stacks  
Generated typealiases that compose all transitive dependencies:

```swift
// Macro generates:
extension CartStorageAdapter {
    typealias Stack = Self  // No dependencies = just Self
}

extension OrderServiceAdapter {  
    typealias Stack = Self & CartStorage.Stack & PaymentService.Stack
}
```

### Environments
Concrete types that provide all platform dependencies:

```swift
struct Environment: OrderServiceAdapter.Stack {
    let database = SQLiteDatabase()      // Satisfies CartStorage requirement
    let paymentGateway = StripeGateway() // Satisfies PaymentService requirement
    // All service methods now available
}
```

### Dependency Sharing
Same-named properties automatically satisfy multiple adapters:

```swift
protocol CartStorageAdapter { var database: Database { get } }
protocol UserStorageAdapter { var database: Database { get } }

struct Environment: CartStorageAdapter.Stack & UserStorageAdapter.Stack {
    let database = SQLiteDatabase()  // Satisfies both requirements
}
```

## Complete Example

```swift
import AdapterStack

// Layer 1: Platform protocols
protocol Database {
    func save(_ key: String, _ data: Data) async throws
    func load(_ key: String) async throws -> Data?
}

protocol PaymentGateway {
    func charge(amount: Decimal, token: String) async throws
}

// Layer 2: Service protocols and adapters
protocol CartStorage {
    func saveCart(_ cart: Cart) async throws
    func loadCart() async throws -> Cart
}

@Adapter(CartStorage.self)
protocol CartStorageAdapter: CartStorage {
    var database: Database { get }
}
// Generated: extension CartStorageAdapter { typealias Stack = Self }

extension CartStorageAdapter {
    func saveCart(_ cart: Cart) async throws {
        let data = try JSONEncoder().encode(cart)
        try await database.save("cart", data)
    }
    
    func loadCart() async throws -> Cart {
        guard let data = try await database.load("cart") else {
            return Cart(items: [])
        }
        return try JSONDecoder().decode(Cart.self, from: data)
    }
}

// Layer 3: Business logic
protocol OrderService {
    func createOrder() async throws -> Order
}

@Adapter(OrderService.self)
protocol OrderServiceAdapter: OrderService, CartStorage, PaymentService {
    // Gets all capabilities through protocol composition
}
// Generated: extension OrderServiceAdapter { 
//     typealias Stack = Self & CartStorage.Stack & PaymentService.Stack 
// }

extension OrderServiceAdapter {
    func createOrder() async throws -> Order {
        let cart = try await loadCart()           // From CartStorage
        let payment = try await processPayment()  // From PaymentService
        return Order(cart: cart, payment: payment)
    }
}

// Layer 4: Feature level
protocol CheckoutService {
    func processCheckout() async throws -> Order
}

@Adapter(CheckoutService.self)
protocol CheckoutServiceAdapter: CheckoutService, OrderService {
    // Composes order service capabilities
}
// Generated: extension CheckoutServiceAdapter {
//     typealias Stack = Self & OrderService.Stack
// }

extension CheckoutServiceAdapter {
    func processCheckout() async throws -> Order {
        return try await createOrder()           // From OrderService
    }
}

// Final environment - just the platform dependencies!
struct CheckoutServiceEnvironment: CheckoutServiceAdapter.Stack {
    let database = SQLiteDatabase()
    let paymentGateway = StripeGateway()
}

// Usage in SwiftUI
struct CheckoutView<Service: CheckoutService>: View {
    let service: Service
    
    var body: some View {
        Button("Complete Order") {
            Task { try await service.processCheckout() }
        }
    }
}

// Works seamlessly
CheckoutView(service: CheckoutServiceEnvironment())
```

## Benefits

### Minimal Boilerplate
```swift
// Before: Manual wiring
let service = OrderServiceImpl(
    cart: CartStorageImpl(database: db),
    payment: PaymentServiceImpl(gateway: gateway)
)

// After: Just declare dependencies
struct Environment: OrderServiceAdapter.Stack {
    let database = db
    let paymentGateway = gateway
}
```

### Type Safety
- Compiler enforces all dependencies are provided
- Protocol boundaries prevent implementation leaks
- Missing dependencies = compile-time errors

### Testing Flexibility
```swift
// Mock entire services
struct MockOrderService: OrderService { /* */ }

// Or mock just the dependencies
struct TestEnvironment: OrderServiceAdapter.Stack {
    let database = MockDatabase()
    let paymentGateway = MockPaymentGateway()
}
```

### SwiftUI Integration
```swift
struct OrderView<Service: OrderService>: View {
    let service: Service
    // View only sees OrderService methods, nothing else
}

// Works with any conforming type
OrderView(service: environment)
OrderView(service: mockService)
```

## Installation

Add as a local package dependency:

```swift
// Package.swift
dependencies: [
    .package(path: "../AdapterStack")
]

// In your target
dependencies: ["AdapterStack"]
```

Or add to Xcode project as local package.

## Requirements

- Swift 5.9+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+

## When to Use

AdapterStack works well for:
- **Medium to large Swift projects** with multiple service layers
- **Teams that value type safety** over dynamic dependency injection  
- **SwiftUI applications** that need clean separation between UI and business logic
- **Projects with complex dependencies** that are hard to wire manually

Consider alternatives if:
- You have simple dependency needs (1-2 services)
- You prefer runtime dependency resolution
- Your team is unfamiliar with protocol-oriented programming

## Design Philosophy

This pattern leverages Swift's protocol system instead of fighting it. Rather than building object graphs, you compose protocol capabilities. Dependencies are shared structurally by name, eliminating explicit wiring while maintaining compile-time safety.

The macro handles the tedious Stack typealias generation, but the architecture remains explicit and understandable.