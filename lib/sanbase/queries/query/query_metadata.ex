defmodule Sanbase.Queries.QueryMetadata do
  @moduledoc ~s"""
  TODO
  """
  @env Application.compile_env(:sanbase, :env)

  @type t :: map()

  @doc ~s"""
  TODO
  """
  @spec from_resolution(Absinthe.Resolution.t()) :: Sanbase.Queries.QueryMetadata.t()
  def from_resolution(resolution) do
    %{context: %{product_code: product_code, auth: %{current_user: user}}} = resolution

    %{
      sanbase_user_id: user.id,
      product: product_code |> to_string() |> String.downcase(),
      query_ran_from_prod_marker: @env == :prod
    }
  end

  @doc false
  def from_local_dev(user_id) when is_integer(user_id) do
    # To be used only in test and dev environment
    %{
      sanbase_user_id: user_id,
      product: "DEV",
      query_ran_from_prod_marker: false
    }
  end

  def sanitize(map) do
    Map.new(map, fn {key, value} ->
      case is_binary(value) do
        # Remove questionmarks and single-quotes. Having them in the query
        # causes the query to fail because of the positional parameters and string
        # variables
        true -> {key, String.replace(value, ~r/['?]/, "")}
        false -> {key, value}
      end
    end)
  end
end
