defmodule SanbaseWeb.Graphql.Middlewares.CalibrateInterval do
  @moduledoc """
  TODO
  """

  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  alias Sanbase.Blockchain.{
    TokenAgeConsumed,
    DailyActiveAddresses,
    TransactionVolume,
    TokenCirculation,
    ExchangeFundsFlow
  }

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Model.Project

  @blockchain_modules [
    TokenAgeConsumed,
    DailyActiveAddresses,
    TransactionVolume,
    TokenCirculation,
    ExchangeFundsFlow
  ]

  def call(
        %Resolution{arguments: %{interval: ""} = args} = resolution,
        middleware_args
      ) do
    %Resolution{
      resolution
      | arguments: Map.merge(args, recalculate_time_args(args, middleware_args))
    }
  end

  def call(resolution, _) do
    resolution
  end

  defp recalculate_time_args(
         %{slug: slug, from: from, to: to},
         %{module: Sanbase.Clickhouse.Github} = middleware_args
       ) do
    with {:ok, github_organization} <- Project.github_organization(slug) do
      min_interval_seconds = Map.get(middleware_args, :min_interval_seconds, 300)
      data_points_count = Map.get(middleware_args, :data_points_count, 50)

      {:ok, from, to, interval} =
        Utils.calibrate_interval(
          Sanbase.Clickhouse.Github,
          github_organization,
          from,
          to,
          "",
          min_interval_seconds,
          data_points_count
        )

      %{from: from, to: to, interval: interval}
    else
      _ -> %{}
    end
  end

  defp recalculate_time_args(
         %{slug: slug, from: from, to: to},
         %{module: module} = middleware_args
       )
       when module in @blockchain_modules do
    min_interval_seconds = Map.get(middleware_args, :min_interval_seconds, 300)
    data_points_count = Map.get(middleware_args, :data_points_count, 50)

    with {:ok, contract_address, _token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             module,
             contract_address,
             from,
             to,
             "",
             min_interval_seconds,
             data_points_count
           ) do
      %{
        from: from,
        to: to,
        interval: interval
      }
    else
      _ -> %{}
    end
  end
end
