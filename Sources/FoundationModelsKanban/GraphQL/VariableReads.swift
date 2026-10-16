import GraphQL

/// The places where an operation reads its variables: the arguments and the directives of the operation, of each
/// selection at all depths, and of each fragment that the operation spreads, also through other fragments.
///
/// The name rewrite reads these places when it takes a removed Rust parameter out of the document. A variable whose
/// only reads were in removed parameters then has no read, and its definition must go out too (divergence.md P4).
/// The `visit` function of the GraphQL module is not public, so this walk visits the syntax tree itself.
enum VariableReads {
    /// Gives each variable node that an operation reads, also in the fragments that it spreads.
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - document: The document of the operation, for its fragment definitions.
    /// - Returns: The variable nodes, in the order that the walk found them. A variable that the operation reads at
    ///   two places gives two nodes.
    static func variables(readBy operation: OperationDefinition, in document: Document) -> [Variable] {
        let fragments = Dictionary(
            document.definitions
                .compactMap { definition in definition as? FragmentDefinition }
                .map { fragment in (fragment.name.value, fragment) }
        ) { first, _ in first }
        var reads = ReadCollector()
        reads.collect(operation.directives)
        reads.collect(operation.selectionSet)
        var visited: Set<String> = []
        var next = 0
        while next < reads.spreads.count {
            let name = reads.spreads[next]
            next += 1
            guard visited.insert(name).inserted, let fragment = fragments[name] else {
                continue
            }
            reads.collect(fragment.directives)
            reads.collect(fragment.selectionSet)
        }
        return reads.variables
    }
}

/// The reads that one walk over some selections found: the variable nodes, and the names of the spread fragments.
private struct ReadCollector {
    /// The variable nodes, in the order that the walk found them.
    private(set) var variables: [Variable] = []

    /// The name of each spread fragment, in the order that the walk found them. A name can be in the list two times.
    private(set) var spreads: [String] = []

    /// Collects the reads of each selection of a selection set, at all depths.
    ///
    /// - Parameter selectionSet: The selection set.
    mutating func collect(_ selectionSet: SelectionSet) {
        for selection in selectionSet.selections {
            collect(selection)
        }
    }

    /// Collects the reads of the arguments of some directives.
    ///
    /// - Parameter directives: The directives.
    mutating func collect(_ directives: [Directive]) {
        for directive in directives {
            collect(directive.arguments)
        }
    }

    /// Collects the reads of one selection: a field, an inline fragment, or a fragment spread.
    ///
    /// - Parameter selection: The selection.
    private mutating func collect(_ selection: any Selection) {
        switch selection {
        case let field as Field:
            collect(field.arguments)
            collect(field.directives)
            if let selectionSet = field.selectionSet {
                collect(selectionSet)
            }
        case let fragment as InlineFragment:
            collect(fragment.directives)
            collect(fragment.selectionSet)
        case let spread as FragmentSpread:
            collect(spread.directives)
            spreads.append(spread.name.value)
        default:
            return
        }
    }

    /// Collects the reads of the values of some arguments.
    ///
    /// - Parameter arguments: The arguments.
    private mutating func collect(_ arguments: [Argument]) {
        for argument in arguments {
            collect(argument.value)
        }
    }

    /// Collects the variables of one value: the value itself, each item of a list, and each field of an `input`
    /// object, at all depths.
    ///
    /// - Parameter value: The value.
    private mutating func collect(_ value: any GraphQL.Value) {
        switch value {
        case let variable as Variable:
            variables.append(variable)
        case let list as ListValue:
            for item in list.values {
                collect(item)
            }
        case let object as ObjectValue:
            for field in object.fields {
                collect(field.value)
            }
        default:
            return
        }
    }
}
