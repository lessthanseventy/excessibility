# Changelog

## v1.0.4

  * Address `CVE-2026-58226`—cap any HPACK variable-length unbounded integers. See also GitHub advisory [GHSA-jj2p-32j7-whj2](https://github.com/elixir-mint/hpax/security/advisories/GHSA-jj2p-32j7-whj2).

## v1.0.3

  * Silence warnings on (upcoming, at this time) Elixir 1.19+.

## v1.0.2

  * The changes in v1.0.1 introduced some subtle compression errors with HPACK encoding. This has been fixed in this version. See [this issue](https://github.com/elixir-mint/hpax/issues/20) for more details.

## v1.0.1

  * Fix some issues with dynamic table resizing. You should not need to do anything to your code, it should Just Work™. If you want to read more, [this issue](https://github.com/elixir-mint/hpax/issues/18) has all the context.

## v1.0.0

  * Silence warnings on Elixir 1.17+.
  * Require Elixir 1.12+.

## v0.2.0

  * Add `HPAX.new/2`, which supports a list of options. For now, the only option
    is `:huffman_encoding`, to choose whether to use Huffman encoding or not.
  * Add `HPAX.encode/3`, which supports encoding all headers with the same
    action.
  * Add the `HPAX.table/0` opaque type.

## v0.1.2

  * Fix `use Bitwise` deprecation warning.

## v0.1.1

  * Improve checking of dynamic resize updates.
