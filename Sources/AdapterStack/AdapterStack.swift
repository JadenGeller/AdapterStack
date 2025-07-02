/// AdapterStack - A Swift macro for generating adapter-stack architecture patterns
///
/// The `@Adapter` macro generates a Stack typealias that composes all dependencies.
/// You must manually add the adapted protocol conformance to your protocol declaration.
///
/// Usage:
/// ```swift
/// @Adapter(OrderService.self)
/// protocol OrderServiceAdapter: OrderService, CartStorage, PaymentService {
///     // Implementation provided by extension
/// }
/// 
/// // Generated:
/// extension OrderServiceAdapter {
///     typealias Stack = Self & CartStorage.Stack & PaymentService.Stack
/// }
/// ```

@attached(extension, names: named(Stack))
public macro Adapter(_ adaptedProtocol: Any.Type) = #externalMacro(
    module: "AdapterStackMacros", 
    type: "AdapterMacro"
)