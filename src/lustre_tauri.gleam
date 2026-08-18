import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/result
import lustre/effect.{type Effect}

// TYPES ---------------------------------------------------------------------

/// Represents possible errors that can occur when working with Tauri commands.
pub type TauriError {
  /// Returned when a Tauri command fails during execution
  InvokeError(String)

  /// Returned when the response from a Tauri command cannot be decoded into
  /// the expected Gleam type
  DecodeError(List(decode.DecodeError))
  /// Json parsing ran into an unexpected end of input.
  JsonUnexpectedEndOfInput
  /// Json parsing ran into an unexpected byte.
  JsonUnexpectedByte(String)
  /// Json parsing ran into an unexpected sequence.
  JsonUnexpectedSequence(String)
}

/// Defines how to handle the response from a Tauri command and convert it into
/// a message for your application. You typically won't need to create this
/// directly - instead use helpers like `expect_json` or `expect_text`.
pub opaque type Expect(message) {
  Expect(run: fn(Result(Dynamic, String)) -> message)
}

// COMMANDS -----------------------------------------------------------------

/// Execute a Tauri command and handle its response. The command name should match
/// one defined in your Tauri backend, and arguments are passed as key-value pairs.
///
/// ### Example
/// ```gleam
/// import lustre_tauri as tauri
///
/// type Msg {
///   FilesSaved(Result(Nil, tauri.TauriError))
/// }
///
/// fn save_files(paths: List(String)) {
///   tauri.invoke(
///     "save_files",
///     [#("paths", paths)],
///     tauri.expect_anything(FilesSaved)
///   )
/// }
/// ```
pub fn invoke(
  command: String,
  args: List(#(String, a)),
  expect: Expect(message),
) -> Effect(message) {
  effect.from(fn(dispatch) {
    do_invoke(command, args)
    |> promise.map(expect.run)
    |> promise.tap(dispatch)
    Nil
  })
}

@external(javascript, "./tauri.ffi.js", "do_invoke")
fn do_invoke(
  command: String,
  args: List(#(String, a)),
) -> Promise(Result(Dynamic, String))

// EXPECTING RESPONSES -------------------------------------------------------

/// Used when you only need to confirm a command succeeded and don't care about
/// its response data. Perfect for fire-and-forget operations like saving files
/// or updating settings.
pub fn expect_anything(
  handler: fn(Result(Nil, TauriError)) -> message,
) -> Expect(message) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.replace(Nil)
    |> handler
  })
}

/// Handle commands that return text responses, such as reading file contents
/// or getting simple string values from your Tauri backend.
pub fn expect_text(
  handler: fn(Result(String, TauriError)) -> message,
) -> Expect(message) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.try(fn(value) {
      case decode.run(value, decode.string) {
        Ok(text) -> Ok(text)
        Error(errs) -> Error(DecodeError(errs))
      }
    })
    |> handler
  })
}

/// Handle commands that return structured data. Uses a decoder to convert the
/// response into a type-safe Gleam value. This is great for commands that
/// return complex data structures like database queries or system information.
///
/// Tauri deserialises command responses before they reach your application, so
/// a command returning a Rust struct arrives as a JavaScript object - use this
/// for those. Use `expect_json` for commands that return raw JSON strings.
///
/// ### Example
/// ```gleam
/// type SystemInfo {
///   SystemInfo(os: String, memory: Int, cpu_cores: Int)
/// }
///
/// fn get_system_info() {
///   let decoder = {
///     use os <- decode.field("os", decode.string)
///     use memory <- decode.field("memory", decode.int)
///     use cpu_cores <- decode.field("cpu_cores", decode.int)
///     decode.success(SystemInfo(os:, memory:, cpu_cores:))
///   }
///
///   tauri.invoke("get_system_info", [], tauri.expect_dynamic(decoder, GotSystemInfo))
/// }
/// ```
pub fn expect_dynamic(
  decoder: Decoder(a),
  handler: fn(Result(a, TauriError)) -> message,
) -> Expect(message) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.try(fn(value) {
      decode.run(value, decoder)
      |> result.map_error(DecodeError)
    })
    |> handler
  })
}

/// Handle commands that return JSON as a string, parsing it with the given
/// decoder. For commands whose response is already structured data (the usual
/// case for a Tauri command returning a struct), use `expect_dynamic` instead.
pub fn expect_json(
  decoder: Decoder(a),
  handler: fn(Result(a, TauriError)) -> message,
) -> Expect(message) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.try(fn(dyn) {
      case decode.run(dyn, decode.string) {
        Ok(json_str) ->
          json.parse(json_str, decoder)
          |> result.map_error(fn(error) {
            case error {
              json.UnexpectedEndOfInput -> JsonUnexpectedEndOfInput
              json.UnexpectedByte(byte) -> JsonUnexpectedByte(byte)
              json.UnexpectedSequence(seq) -> JsonUnexpectedSequence(seq)
              json.UnableToDecode(decode_errors) -> DecodeError(decode_errors)
            }
          })
        Error(decode_errors) -> Error(DecodeError(decode_errors))
      }
    })
    |> handler
  })
}
