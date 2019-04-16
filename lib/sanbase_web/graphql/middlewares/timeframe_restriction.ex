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

  alias Absinthe.Resolution
  alias Sanbase.Auth.User

  @allow_access_without_staking ["santiment"]

  # Allow access to historical data and real-time data for the Santiment project.
  # This will serve the purpose of showing to anonymous and not-staking users how
  # the data looks like.
  def call(
        %Resolution{
          arguments: %{slug: slug}
        } = resolution,
        _
      )
      when slug in @allow_access_without_staking do
    resolution
    |> check_from_to_params()
  end

  def call(
        %Resolution{
          context: %{
            auth: %{auth_method: method, current_user: current_user}
          },
          arguments: %{from: from, to: to} = args
        } = resolution,
        middleware_args
      )
      when method in [:user_token, :apikey] do
    if !has_enough_san_tokens?(current_user) do
      %Resolution{
        resolution
        | arguments: %{
            args
            | from: restrict_from(from, middleware_args),
              to: restrict_to(to, middleware_args)
          }
      }
    else
      resolution
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
    restrict_to = Timex.shift(Timex.now(), days: restrict_to_in_days())
    Enum.min_by([to_datetime, restrict_to], &DateTime.to_unix/1)
  end

  defp restrict_from(from_datetime, %{allow_historical_data: true}), do: from_datetime

  defp restrict_from(from_datetime, _) do
    restrict_from = Timex.shift(Timex.now(), days: restrict_from_in_days())
    Enum.max_by([from_datetime, restrict_from], &DateTime.to_unix/1)
  end

  defp required_san_stake_full_access() do
    Config.module_get(Sanbase, :required_san_stake_full_access) |> String.to_integer()
  end

  defp restrict_to_in_days() do
    -1 * (Config.get(:restrict_to_in_days) |> String.to_integer())
  end

  defp restrict_from_in_days do
    -1 * (Config.get(:restrict_from_in_days) |> String.to_integer())
  end

  defp check_from_to_params(%Resolution{arguments: %{from: from, to: to}} = resolution) do
    if DateTime.compare(from, to) == :gt do
      resolution
      |> Resolution.put_result(
        {:error,
         """
         `from` and `to` are not a valid time range.
         Either `from` is a datetime after `to` or the time range is outside of the allowed interval.
         """}
      )
    else
      resolution
    end
  end

  defp check_from_to_params(resolution), do: resolution
end
