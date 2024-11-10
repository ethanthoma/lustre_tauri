# lustre_tauri

[![Package Version](https://img.shields.io/hexpm/v/lustre_tauri)](https://hex.pm/packages/lustre_tauri)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lustre_tauri/)

Use [Tauri](https://tauri.app/) invoke commands from [Lustre](https://hex.pm/packages/lustre) via its `effect` interface.

The API and details are heavily based on [lustre_http](https://hexdocs.pm/lustre_http/index.html).

> [!NOTE]
> This library currently only supports invoke commands, not events

---

## Requirements

This requires that you have the [`@tauri-apps/api`](https://www.npmjs.com/package/@tauri-apps/api) package installed.

## Example

```gleam
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_tauri.{type TauriError}

pub fn main() {
    let app = lustre.application(init, update, view)
}

type Model {
    Model(name: String, message: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
    #(Model(name: "", message: ""), effect.none())
}

pub opaque type Msg {
    UpdateName(String)
    GreetUser(Result(String, TauriError))
    Greet
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UpdateName(name) -> #(Model(..model, name: name), effect.none())
    GreetUser(Ok(message)) -> #(
      Model(..model, message: message),
      effect.none(),
    )
    GreetUser(Error(_)) -> #(model, effect.none())
    Greet -> #(model, greet(model.name))
  }
}

fn greet(name: String) -> Effect(Msg) {
    lustre_tauri.invoke(
        "greet",
        [],
        lustre_tauri.expect_text(GreetUser)
    )
}

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [element.text(model.message)]),
    html.input([
      attribute.type_("text"),
      attribute.name("greet_name"),
      event.on_input(UpdateName),
    ]),
    html.button([event.on_click(Greet)], [element.text("Send your name!")]),
  ])
}
```

## Installation

Like Lustre, this is published on [Hex](https://hex.pm/packages/lustre_tauri). 
You can add it to your Gleam project via

```sh
gleam add lustre_tauri
```

You will also need to install the `@tauri-apps/api`. This can be added to your 
project through your preferred method:

```sh
pnpm add @tauri-apps/api
yarn add @tauri-apps/api
npm add @tauri-apps/api
```

## Development

```sh
gleam run   # Run the project
```

Further documentation can be found at <https://hexdocs.pm/lustre_tauri>.
