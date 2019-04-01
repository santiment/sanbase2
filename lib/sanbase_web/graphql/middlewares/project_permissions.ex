defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(resolution, _) do
    case not_allowed_fields(resolution) do
      [] ->
        resolution

      fields ->
        resolution
        |> Resolution.put_result(
          {:error, "Cannot query #{inspect(fields)} on a query that returns more than 1 project."}
        )
    end
  end

  # Helper functions

  defp not_allowed_fields(resolution) do
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

    Enum.reduce(requested_fields, [], fn {key, _}, acc ->
      case Enum.member?(not_allowed_fields, key |> Macro.underscore()) do
        true -> [key | acc]
        false -> acc
      end
    end)
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&Map.get(&1, :name))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end
end
