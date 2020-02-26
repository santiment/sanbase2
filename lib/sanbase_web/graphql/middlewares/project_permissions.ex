defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Helpers.Utils

  def call(%Resolution{} = resolution, _) do
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
      "initialIco",
      "ethSpentOverTime",
      "ethTopTransactions",
      "tokenTopTransactions",
      "fundsRaisedIcos",
      "fundsRaisedEthIcoEndPrice",
      "fundsRaisedUsdIcoEndPrice",
      "fundsRaisedBtcIcoEndPrice",
      "availableMetrics",
      "availableTimeseriesMetrics",
      "availableHistogramMetrics",
      "availableQueries"
    ]

    requested_fields = Utils.requested_fields(resolution)

    Enum.reduce(requested_fields, [], fn key, acc ->
      case Enum.member?(not_allowed_fields, key) do
        true -> [key | acc]
        false -> acc
      end
    end)
  end
end
