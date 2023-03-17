# Excessibility

## What is it for?

Excessibility allows you to easily take snapshots of the DOM at any given point in your ExUnit or Wallaby Tests. These snapshots can then be passed to [pa11y](https://github.com/pa11y/pa11y) to test for WCAG compliance.

## Installation

The package can be installed by adding `excessibility` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.1.0"}
  ]
end
```

## Usage

Simply call Excessibility.here() and pass it either a Phoenix Conn or a Wallaby Session. It will produce an html file named with the module and line number it was called from.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/excessibility>.

