# Babble

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `babble` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:babble, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/babble](https://hexdocs.pm/babble).

## TODO

- 🗴 Honor `:rate` parameter of `Babble.subscribe` (rate decimation)
- 🗴 Remote publication (native transport)
- 🗴 Remote publication (UDP multicast transport)
- 🗴 Efficient message format
  - 🗴 Message keys published separately from message values
  - 🗴 Compression
  - 🗴 HMAC based on node cookie to filter messages from other node clusters
- 🗴 Message timestamps
  - 🗴 Honor `:stale_time` parameter of `Babble.poll`
- 🗴 Multi-node test suite
