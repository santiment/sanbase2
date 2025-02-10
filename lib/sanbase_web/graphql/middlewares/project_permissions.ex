defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Helpers.Utils

  def call(%Resolution{} = resolution, _) do
    case not_allowed_fields(resolution) do
      [] ->
        resolution

      fields ->
        Resolution.put_result(
          resolution,
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
      if Enum.member?(not_allowed_fields, key) do
        [key | acc]
      else
        acc
      end
    end)
  end
end
