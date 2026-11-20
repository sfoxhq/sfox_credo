defmodule SfoxCredo.Support.FencedDoctestTest do
  use ExUnit.Case, async: true

  doctest SfoxCredo.Support.FencedDoctest

  # Guards against the doctests above silently finding nothing: the fenced
  # examples must produce three doctests.
  test "every fenced doctest is collected" do
    doctests =
      :functions
      |> __MODULE__.__info__()
      |> Enum.filter(fn {name, _arity} ->
        name
        |> to_string()
        |> String.starts_with?("doctest ")
      end)

    assert length(doctests) == 3
  end
end
