defmodule SanbaseWeb.Graphql.Middlewares.TimeframeRestriction do
  @moduledoc """
  Middleware that is used to restrict the API access in a certain timeframe.
  The restriction is for anon users and for users without the required SAN stake.
  By default configuration the allowed timeframe is in the inteval [now() - 90days, now() - 1day]
  """
  @behaviour Absinthe.Middleware

  @compile :inline_list_funcs
  @compile {:inline,
            restrict_from: 2,
            restrict_to: 2,
            check_from_to_params: 1,
            has_enough_san_tokens?: 1,
            required_san_stake_full_access: 0,
            restrict_to_in_days: 0,
            restrict_from_in_days: 0}

  require Sanbase.Utils.Config, as: Config
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Absinthe.Resolution
  alias Sanbase.Auth.User

  @allow_access_without_staking ["santiment"]

  @minimal_datetime_param from_iso8601!("2009-01-01T00:00:00Z")

  def call(resolution, %{allow_realtime_data: true, allow_historical_data: true}) do
    resolution |> check_from_to_params()
  end

  # Allow access to historical data and real-time data for the Santiment project.
  # This will serve the purpose of showing to anonymous and not-staking users how
  # the data looks like.
  def call(%Resolution{arguments: %{slug: slug}} = resolution, _)
      when slug in @allow_access_without_staking do
    resolution
    |> check_from_to_params()
  end

  def call(
        %Resolution{
          context: %{auth: %{current_user: current_user}},
          arguments: %{from: from, to: to} = args
        } = resolution,
        middleware_args
      ) do
    if has_enough_san_tokens?(current_user) do
      resolution
    else
      %Resolution{
        resolution
        | arguments: %{
            args
            | from: restrict_from(from, middleware_args),
              to: restrict_to(to, middleware_args)
          }
      }
    end
    |> check_from_to_params()
  end

  def call(%Resolution{arguments: %{from: from, to: to} = args} = resolution, middleware_args) do
    %Resolution{
      resolution
      | arguments: %{
          args
          | from: restrict_from(from, middleware_args),
            to: restrict_to(to, middleware_args)
        }
    }
    |> check_from_to_params()
  end

  def call(resolution, _) do
    resolution
    |> check_from_to_params()
  end

  defp has_enough_san_tokens?(current_user) do
    Decimal.cmp(
      User.san_balance!(current_user),
      Decimal.new(required_san_stake_full_access())
    ) != :lt
  end

  defp restrict_to(to_datetime, %{allow_realtime_data: true}), do: to_datetime

  defp restrict_to(to_datetime, _) do
    restrict_to = Timex.shift(Timex.now(), days: -restrict_to_in_days())
    Enum.min_by([to_datetime, restrict_to], &DateTime.to_unix/1)
  end

  defp restrict_from(from_datetime, %{allow_historical_data: true}), do: from_datetime

  defp restrict_from(from_datetime, _) do
    restrict_from = Timex.shift(Timex.now(), days: -restrict_from_in_days())
    Enum.max_by([from_datetime, restrict_from], &DateTime.to_unix/1)
  end

  defp required_san_stake_full_access() do
    Config.module_get(Sanbase, :required_san_stake_full_access) |> String.to_integer()
  end

  defp restrict_to_in_days() do
    Config.get(:restrict_to_in_days) |> String.to_integer()
  end

  defp restrict_from_in_days do
    Config.get(:restrict_from_in_days) |> String.to_integer()
  end

  defp to_param_is_after_from(from, to) do
    if DateTime.compare(to, from) == :gt do
      true
    else
      {:error,
       """
       `from` and `to` are not a valid time range.
       Either `from` is a datetime after `to` or the time range is outside of the allowed interval.
       """}
    end
  end

  defp from_or_to_params_are_after_minimal_datetime(from, to) do
    if DateTime.compare(from, @minimal_datetime_param) == :gt and
         DateTime.compare(to, @minimal_datetime_param) == :gt do
      true
    else
      {:error,
       """
       Cryptocurrencies didn't existed before #{@minimal_datetime_param}.
       Please check `from` or `to` param values.
       """}
    end
  end

  defp check_from_to_params(%Resolution{arguments: %{from: from, to: to}} = resolution) do
    with true <- to_param_is_after_from(from, to),
         true <- from_or_to_params_are_after_minimal_datetime(from, to) do
      resolution
    else
      {:error, _message} = error ->
        resolution
        |> Resolution.put_result(error)
    end
  end

  defp check_from_to_params(resolution), do: resolution
end
