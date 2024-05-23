defmodule Sanbase.Queries.QueryMetadata do
  @moduledoc ~s"""
  Holds the metadata of the query execution.

  This data is used to add metadata to the executed queries
  so some analysis in Clickhouse can be done to determine which
  user executed what query, without needing to access our postgres
  database.
  """
  @env Application.compile_env(:sanbase, :env)
  @is_prod @env == :prod
  @type t :: map()

  @doc ~s"""
  Create a new metadata from a Absinthe resolution of a logged-in user.
  """
  @spec from_resolution(Absinthe.Resolution.t()) ::
          Sanbase.Queries.QueryMetadata.t() | no_return()
  def from_resolution(%{context: %{requested_product: product_code, auth: %{current_user: user}}}) do
    %{
      sanbase_user_id: user.id,
      product: product_code |> to_string() |> String.downcase(),
      query_ran_from_prod_marker: @is_prod
    }
  end

  def from_resolution(_) do
    raise(RuntimeError, """
    Trying to create a Queries.QueryMetadata map with Absinthe.Resolution
    that is missing the product_code and/or current_user in the context.
    Most probably this is due to a programmer's error not ensuring that this
    function is called only for logged-in users.
    """)
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

  def from_refresh_job() do
    %{
      sanbase_user_id: 0,
      product: "REFRESH",
      query_ran_from_prod_marker: @is_prod
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
