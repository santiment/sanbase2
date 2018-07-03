defmodule SanbaseWeb.Graphql.Middlewares.ApiDelay do
  @moduledoc """
  Middleware that is used to add artificial delay for the data our API returns.
  The delay is for anon users and for users without the required SAN stake.
  Currently the delay is one day and is achieved by transforming the `to` datetime
  argument, taking the minimum between the original `to` and now() - 1day.
  """

  @behaviour Absinthe.Middleware

  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config
  alias Absinthe.Resolution
  alias Sanbase.Auth.User

  def call(
        %Resolution{
          context: %{
            auth: %{auth_method: method, current_user: current_user}
          },
          arguments: %{to: _to}
        } = resolution,
        _
      )
      when method in [:user_token, :apikey] do
    if !has_enough_san_tokens?(current_user) do
      update_in(resolution.arguments.to, &delay_1day(&1))
    else
      resolution
    end
  end

  def call(%Resolution{arguments: %{to: _to}} = resolution, _) do
    update_in(resolution.arguments.to, &delay_1day(&1))
  end

  def call(resolution, _) do
    resolution
  end

  defp has_enough_san_tokens?(current_user) do
    Decimal.cmp(
      User.san_balance!(current_user),
      Decimal.new(required_san_stake_realtime_api())
    ) != :lt
  end

  defp delay_1day(to_datetime) do
    yesterday = Timex.shift(Timex.now(), days: -1)
    Enum.min_by([to_datetime, yesterday], &DateTime.to_unix/1)
  end

  defp required_san_stake_realtime_api() do
    Config.get(:required_san_stake_realtime_api) |> String.to_integer()
  end
end
