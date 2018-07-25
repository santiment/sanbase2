defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _) do
    resolution
  end

  def call(%Resolution{context: %{auth: %{auth_method: method}}} = resolution, config)
      when method in [:user_token, :apikey] do
    all_projects? = Keyword.get(config, :all_projects?, false)

    if all_projects? and has_not_allowed_fields?(resolution) do
      resolution
      |> Resolution.put_result({:error, :unauthorized})
    else
      resolution
    end
  end

  def call(resolution, _) do
    if has_not_allowed_fields?(resolution) do
      resolution
      |> Resolution.put_result({:error, :unauthorized})
    else
      resolution
    end
  end

  # Helper functions

  defp has_not_allowed_fields?(resolution) do
    not_allowed_fields = [
      "icos",
      "initial_ico",
      "eth_spent_over_time",
      "eth_top_transactions",
      "token_top_transactions",
      "funds_raised_icos",
      "funds_raised_eth_ico_end_price",
      "funds_raised_usd_ico_end_price",
      "funds_raised_btc_ico_end_price"
    ]

    requested_fields = requested_fields(resolution)

    Enum.any?(not_allowed_fields, fn field ->
      Map.has_key?(requested_fields, field)
    end)
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&Map.get(&1, :name))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end
end
