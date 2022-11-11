# ExampleDistributedSystem
## Setup
open a shell and run 
>  iex --name a@127.0.0.1 -S mix

open another shell and run 

>  iex --name b@127.0.0.1 -S mix 

open a third shell and run

>  iex --name c@127.0.0.1 -S mix

The naming is not arbitrary, these are the names supported in the config file, any other name would have to added to the config file before running the app. Because the nodes connecting depends on whats in  the config file. 

The testing of various criteria is a bit manual currently, you stop senior node and watch elections happen and the next senior node take over, start the senior node again and watch the junior node surrender control. Notice the effect of adding a junior node to the cluster or removing it, do the same for senior nodes.


Improvements to be made.

* make the name discovery of nodes and connection dynamic and not static


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `example_distributed_system` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:example_distributed_system, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/example_distributed_system>.

