# Excessibility

## What is it for?

Excessibility allows you to easily take snapshots of the DOM at any given point
in your ExUnit or Wallaby Tests. These snapshots can then be passed to
[pa11y](https://github.com/pa11y/pa11y) to test for WCAG compliance.

## Installation

The package can be installed by adding `excessibility` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.3.0"}
  ]
end
```

## Usage

Simply call Excessibility.html_snapshot() and pass it either a Phoenix Conn or a
Wallaby Session. It will produce an html file named with the module and line
number it was called from.

The module also includes a mix task that you can call to run pa11y against the
snapshots. `MIX_ENV=test mix excessibility`

## Default Configuration

```
config :excessibility,
  :assets_task, "assets.deploy",
  :pa11y_path, "/assets/node_modules/pa11y/bin/pa11y.js",
  :output_path, "test/excessibility"
```

Documentation can be generated with
[ExDoc](https://github.com/elixir-lang/ex_doc) and published on
[HexDocs](https://hexdocs.pm). Once published, the docs can be found at
<https://hexdocs.pm/excessibility>.
