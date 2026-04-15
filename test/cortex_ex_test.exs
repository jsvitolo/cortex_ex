defmodule CortexExTest do
  use ExUnit.Case
  doctest CortexEx

  test "greets the world" do
    assert CortexEx.hello() == :world
  end
end
