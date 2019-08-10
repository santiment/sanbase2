defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [fit_from_datetime: 2, calibrate_interval: 7]

  import Sanbase.Utils.ErrorHandling,
    only: [log_graphql_error: 2, graphql_error_msg: 2]

  alias Sanbase.Model.Project

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  alias Sanbase.Blockchain.ExchangeFundsFlow

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 50

  def token_age_consumed(_root, args, resolution) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "stack_age_consumed")
    })
    |> transform_values(:stack_age_consumed)
  end

  @doc ~S"""
  Return the average age of the tokens that were transacted for the given slug and time period.
  """
  def average_token_age_consumed_in_days(_root, _args, _resolution) do
    # TODO
    {:ok, []}
  end

  def transaction_volume(_root, args, resolution) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "transaction_volume")
    })
    |> transform_values(:transaction_volume)
  end

  @doc ~S"""
  Return the amount of tokens that were transacted in or out of an exchange wallet for a given slug
  and time period
  """
  def exchange_funds_flow(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval
        } = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(ExchangeFundsFlow, contract, from, to, interval, 3600, @datapoints),
         {:ok, exchange_funds_flow} <-
           ExchangeFundsFlow.transactions_in_out_difference(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, exchange_funds_flow |> fit_from_datetime(args)}
    else
      {:error, error} ->
        error_msg = graphql_error_msg("Exchange Funds Flow", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  defp transform_values({:error, error}, _), do: {:error, error}

  defp transform_values({:ok, data}, value_name) do
    data =
      data
      |> Enum.map(fn %{datetime: datetime, value: value} ->
        %{
          value_name => value,
          datetime: datetime
        }
      end)

    {:ok, data}
  end
end
