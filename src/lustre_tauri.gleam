import gleam/dynamic.{type Decoder, type Dynamic}
import gleam/javascript/promise.{type Promise}
import gleam/result
import lustre/effect.{type Effect}

// TYPES ---------------------------------------------------------------------

/// Represents possible errors that can occur when working with Tauri commands.
pub type TauriError {
  /// Returned when a Tauri command fails during execution
  InvokeError(String)

  /// Returned when the response from a Tauri command cannot be decoded into
  /// the expected Gleam type
  DecodeError(List(dynamic.DecodeError))
}

/// Defines how to handle the response from a Tauri command and convert it into
/// a message for your application. You typically won't need to create this
/// directly - instead use helpers like `expect_json` or `expect_text`.
pub opaque type Expect(msg) {
  Expect(run: fn(Result(Dynamic, String)) -> msg)
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
  expect: Expect(msg),
) -> Effect(msg) {
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
  to_msg: fn(Result(Nil, TauriError)) -> msg,
) -> Expect(msg) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.replace(Nil)
    |> to_msg
  })
}

/// Handle commands that return text responses, such as reading file contents
/// or getting simple string values from your Tauri backend.
pub fn expect_text(to_msg: fn(Result(String, TauriError)) -> msg) -> Expect(msg) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.then(fn(value) {
      case dynamic.string(value) {
        Ok(text) -> Ok(text)
        Error(errs) -> Error(DecodeError(errs))
      }
    })
    |> to_msg
  })
}

/// Handle commands that return structured data. Uses a decoder to convert the
/// response into a type-safe Gleam value. This is great for commands that
/// return complex data structures like database queries or system information.
///
/// ### Example
/// ```gleam
/// type SystemInfo {
///   SystemInfo(os: String, memory: Int, cpu_cores: Int)
/// }
///
/// fn get_system_info() {
///   let decoder = dynamic.decode3(
///     SystemInfo,
///     dynamic.field("os", dynamic.string),
///     dynamic.field("memory", dynamic.int),
///     dynamic.field("cpu_cores", dynamic.int)
///   )
///   
///   tauri.invoke("get_system_info", [], tauri.expect_json(decoder, GotSystemInfo))
/// }
/// ```
pub fn expect_json(
  decoder: Decoder(a),
  to_msg: fn(Result(a, TauriError)) -> msg,
) -> Expect(msg) {
  Expect(fn(response) {
    response
    |> result.map_error(InvokeError)
    |> result.then(fn(value) {
      case decoder(value) {
        Ok(decoded) -> Ok(decoded)
        Error(errs) -> Error(DecodeError(errs))
      }
    })
    |> to_msg
  })
}
