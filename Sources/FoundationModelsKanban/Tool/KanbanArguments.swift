import FoundationModels
import FoundationModelsExtras

/// The arguments of one call of the `kanban` tool: one GraphQL document, the values of its variables, and the
/// operation to run (plan.md §7.1, §12 item 8).
///
/// The decode and the schema are the ones of the toolkit ``GraphQLArguments``. The decode is forgiving about
/// `variables`. A code-mode script sends a plain object. A model, for example Qwen 3.8
/// (`mlx-community/Qwen3.8-27B-mxfp4`), sends a string that holds a JSON object, sometimes in a code fence. Each of
/// these forms gives the same variables. `null`, an empty object, an empty string, and no key give no variables. Any
/// other value does not make the decode throw: it sets the `variablesError` of the request, and the tool then returns
/// the error `INVALID_VARIABLES`. The decode throws only when the `query` is missing.
///
/// The model test in `IntegrationTests/` uses Qwen 3.8, and Qwen 3.8 sent the string form with the value in 3 of 3
/// runs. The on-device `SystemLanguageModel` sent `"variables": {}` in 3 of 3 runs, because guided generation picked
/// the object choice with no properties (plan.md §7.1).
public struct KanbanArguments: ConvertibleFromGeneratedContent, Sendable {
    /// The document, the variables, and the operation of the call, as the toolkit decodes them.
    let request: GraphQLArguments

    /// The schema of the arguments that the model and Multitool see: ``GraphQLArguments/generationSchema``.
    ///
    /// `variables` is `anyOf` a string and an object with no properties, so its encoded JSON Schema has no `type`.
    /// Multitool checks the `type` of each top-level argument before it calls the tool, and it does not check an
    /// argument with no `type`. Thus, a script can send a plain object.
    static var generationSchema: GenerationSchema {
        GraphQLArguments.generationSchema
    }

    /// Decodes the arguments of one call.
    ///
    /// - Parameter content: The arguments object that the model or the script sent.
    /// - Throws: ``GraphQLArguments/MissingQueryError`` when the content is not an object with a `query` string. A
    ///   `variables` value that is not a JSON object does not throw: it sets the `variablesError` of the request.
    public init(_ content: GeneratedContent) throws {
        request = try GraphQLArguments(content)
    }
}
