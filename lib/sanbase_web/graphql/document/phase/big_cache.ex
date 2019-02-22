defmodule SanbaseWeb.Graphql.Phase.BigCache do
  @moduledoc false

  use Absinthe.Phase

  @hash_format_error %Absinthe.Phase.Error{
    phase: __MODULE__,
    message: "HashFormatIncorrect"
  }

  @doc false
  def run(_, options \\ [])

  def run({:apq_hash_format_error, _}, _options) do
    result_with_error(@hash_format_error)
  end

  def run({:graphql_cache_hit, document}, _options) do
    {:ok, document}
  end

  defp result_with_error(error) do
    {:jump, %Absinthe.Blueprint{errors: [error]}, Absinthe.Phase.Document.Validation.Result}
  end
end
