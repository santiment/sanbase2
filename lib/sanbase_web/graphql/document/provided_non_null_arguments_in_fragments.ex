defmodule SanbaseWeb.Graphql.Phase.Document.Validation.ProvidedNonNullArgumentsInFragments do
  @moduledoc """
  Rejects missing non-null arguments on fields inside named fragments.

  Absinthe's `ProvidedNonNullArguments` walks only the current operation, so a
  required argument left out of a field in a named fragment passes validation. The
  field's complexity function and resolver then get args without that key and crash.
  This phase applies the same check to the fragments, with the same error message.
  """
  use Absinthe.Phase

  alias Absinthe.Blueprint
  alias Absinthe.Phase.Document.Validation.ProvidedNonNullArguments

  @spec run(Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(%Blueprint{} = input, _options \\ []) do
    fragments =
      Enum.map(input.fragments, fn fragment ->
        Blueprint.prewalk(fragment, &handle_node(&1, input.schema))
      end)

    {:ok, %{input | fragments: fragments}}
  end

  defp handle_node(%Blueprint.Input.Argument{value: nil, flags: %{missing: _}} = node, schema) do
    type_name = Absinthe.Type.name(node.schema_node.type, schema)

    error = %Absinthe.Phase.Error{
      phase: __MODULE__,
      message: ProvidedNonNullArguments.error_message(node.name, type_name),
      locations: [node.source_location]
    }

    {:halt, put_error(node, error)}
  end

  defp handle_node(node, _schema), do: node
end
