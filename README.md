# Excessibility

## What is it for?

Excessibility allows you to easily take snapshots of the DOM at any given point in your ExUnit or Wallaby Tests.<br/>
These snapshots can then be passed to [pa11y](https://github.com/pa11y/pa11y) to test for WCAG compliance.

## Installation

The package can be installed by adding `excessibility` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.3.0"}
  ]
end
```

You'll also need to install `pa11y`:

```sh
npm i pa11y --save-dev --prefix=./assets/
```

## Usage

To use it `require Excessibility` and then call `Excessibility.html_snapshot/2` and pass it any of:

- a Phoenix Conn
- a Wallaby Session
- a LiveViewTest View struct

It will produce an html file named with the module and line number of where it was called from.

You can pass an optional argument of `open_browser?: true` to open the snapshot in your browser.

```elixir
thing
|> html_snapshot(open_browser?: true)
```

The module also includes a mix task that you can call to run [pa11y](https://github.com/pa11y/pa11y) against the snapshots.<br/>
`MIX_ENV=test mix excessibility`

You may want to add `Excessbility` as an `import` or `require` in your `ConnCase` or `FeatureCase`.

## Default Configuration

```elixir
config :excessibility,
  :assets_task, "assets.deploy",
  :pa11y_path, "/assets/node_modules/pa11y/bin/pa11y.js",
  :output_path, "test/excessibility"
```

## Pa11y Configuration

See the [pa11y documentation](https://github.com/pa11y/pa11y#configuration) for configuration options.

Documentation can be generated with:<br/>
[ExDoc](https://github.com/elixir-lang/ex_doc) and published on<br/>
[HexDocs](https://hexdocs.pm). Once published, the docs can be found at<br/>
<https://hexdocs.pm/excessibility>.
