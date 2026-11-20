defmodule SfoxCredo.Support.FencedDoctest do
  @moduledoc """
  Doctests inside fenced code blocks. `SfoxCredo.Support.FencedDoctestTest`
  runs them, so CI on every supported Elixir version shows that a closing fence
  ends a doctest's expected result.
  """

  @doc """
  Doubles `number`.

  ```elixir
  iex> SfoxCredo.Support.FencedDoctest.double(2)
  4
  ```

  Several doctests can share one fence when a blank line separates them:

  ```elixir
  iex> SfoxCredo.Support.FencedDoctest.double(0)
  0

  iex> SfoxCredo.Support.FencedDoctest.double(-3)
  -6
  ```
  """
  @spec double(number()) :: number()
  def double(number), do: number * 2
end
