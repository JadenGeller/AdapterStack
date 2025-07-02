import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

enum AdapterMacroDiagnostic {
    case invalidArgument
    case onlyApplicableToProtocol
    case protocolShouldConformToAdaptedProtocol(String)
}

extension AdapterMacroDiagnostic: DiagnosticMessage {
    func diagnose(at node: some SyntaxProtocol) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: self)
    }
    
    var message: String {
        switch self {
        case .invalidArgument:
            return "@Adapter requires a protocol type as argument (e.g., @Adapter(MyProtocol.self))"
        case .onlyApplicableToProtocol:
            return "@Adapter can only be applied to protocol declarations"
        case .protocolShouldConformToAdaptedProtocol(let protocolName):
            return "Protocol should conform to '\(protocolName)' for the adapter pattern to work correctly"
        }
    }
    
    var diagnosticID: MessageID {
        MessageID(domain: "AdapterStackMacros", id: "AdapterMacro.\(self)")
    }
    
    var severity: DiagnosticSeverity {
        switch self {
        case .invalidArgument, .onlyApplicableToProtocol:
            return .error
        case .protocolShouldConformToAdaptedProtocol:
            return .warning
        }
    }
}


public struct AdapterMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(AdapterMacroDiagnostic.onlyApplicableToProtocol.diagnose(at: declaration))
            return []
        }
        
        guard let adaptedProtocol = extractProtocolName(from: node) else {
            context.diagnose(AdapterMacroDiagnostic.invalidArgument.diagnose(at: node))
            return []
        }
        
        // Check if protocol already conforms to adapted protocol (helpful warning)
        let conformsToAdaptedProtocol = protocolDecl.inheritanceClause?.inheritedTypes.contains { inheritedType in
            if let identifier = inheritedType.type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text == adaptedProtocol
            }
            return false
        } ?? false
        
        if !conformsToAdaptedProtocol {
            context.diagnose(AdapterMacroDiagnostic.protocolShouldConformToAdaptedProtocol(adaptedProtocol).diagnose(at: protocolDecl.name))
        }
        
        // Collect dependency stacks from inherited protocols
        var dependencyStacks: [String] = []
        
        if let inheritanceClause = protocolDecl.inheritanceClause {
            for inheritedType in inheritanceClause.inheritedTypes {
                if let identifier = inheritedType.type.as(IdentifierTypeSyntax.self) {
                    let inheritedName = identifier.name.text
                    // Skip the adapted protocol itself and common base protocols
                    if inheritedName != adaptedProtocol && 
                       !["Sendable", "Equatable", "Hashable", "Codable"].contains(inheritedName) {
                        dependencyStacks.append("\(inheritedName).Stack")
                    }
                }
            }
        }
        
        // Build the Stack typealias composition
        let stackComposition: String
        if dependencyStacks.isEmpty {
            stackComposition = "Self"
        } else {
            stackComposition = "Self & \(dependencyStacks.joined(separator: " & "))"
        }
        
        let extensionDecl = ExtensionDeclSyntax(
            extendedType: type,
            memberBlock: MemberBlockSyntax {
                DeclSyntax("typealias Stack = \(raw: stackComposition)")
            }
        )
        
        return [extensionDecl]
    }
    
    private static func extractProtocolName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
              let baseName = memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text else {
            return nil
        }
        return baseName
    }
}

@main
struct AdapterStackMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AdapterMacro.self
    ]
}