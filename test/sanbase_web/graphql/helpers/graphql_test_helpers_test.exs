defmodule SanbaseWeb.Graphql.TestHelpersTest do
  use ExUnit.Case, async: true

  import SanbaseWeb.Graphql.TestHelpers

  # The default inspect limit differs between elixir versions - 50 before 1.19
  # and 200 after it. Use values bigger than any of these defaults, so a
  # truncation regression is caught no matter the version that runs the tests.
  # A truncated list/string is rendered with a trailing `...`, which is lexed
  # by absinthe as the spread token and makes the whole document invalid
  @list_size 300
  @string_size 10_000

  test "long lists are not truncated" do
    slugs = Enum.map(1..@list_size, fn i -> "slug-#{i}" end)

    args = map_to_args(%{selector: %{slugs: slugs, map_as_input_object: true}})

    refute args =~ "..."
    assert args =~ ~s|"slug-1"|
    assert args =~ ~s|"slug-#{@list_size}"|
    assert parse_document("{ githubActivityStats(#{args}){ slug } }") == :ok
  end

  test "long strings are not truncated" do
    text = String.duplicate("a", @string_size)

    args = map_to_args(%{text: text})

    refute args =~ "..."
    assert args =~ text
  end

  defp parse_document(document) do
    pipeline =
      SanbaseWeb.Graphql.Schema
      |> Absinthe.Pipeline.for_document()
      |> Absinthe.Pipeline.upto(Absinthe.Phase.Parse)

    case Absinthe.Pipeline.run(document, pipeline) do
      {:ok, _blueprint, _phases} -> :ok
      {:error, error, _phases} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
