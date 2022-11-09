defmodule ExampleDistributedSystemTest do
  use ExUnit.Case
  doctest ExampleDistributedSystem

  test "greets the world" do
    assert ExampleDistributedSystem.hello() == :world
  end
end
