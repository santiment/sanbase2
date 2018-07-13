defmodule SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction do
  @moduledoc """
  Middleware that is used to restrict the API access in a certain timeframe.
  The restriction is for anon users and for users without the required SAN stake.
  By default configuration the allowed timeframe is in the inteval [now() - 90days, now() - 1day]
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
          arguments: %{from: from, to: to} = args
        } = resolution,
        _
      )
      when method in [:user_token, :apikey] do
    if !has_enough_san_tokens?(current_user) do
      %Resolution{
        resolution
        | arguments: %{args | from: restrict_from(from), to: restrict_to(to)}
      }
    else
      resolution
    end
  end

  def call(%Resolution{arguments: %{from: from, to: to} = args} = resolution, _) do
    %Resolution{resolution | arguments: %{args | from: restrict_from(from), to: restrict_to(to)}}
  end

  def call(resolution, _) do
    resolution
  end

  defp has_enough_san_tokens?(current_user) do
    Decimal.cmp(
      User.san_balance!(current_user),
      Decimal.new(required_san_stake_full_access())
    ) != :lt
  end

  defp restrict_to(to_datetime) do
    restrict_to = Timex.shift(Timex.now(), days: restrict_to_in_days())
    Enum.min_by([to_datetime, restrict_to], &DateTime.to_unix/1)
  end

  defp restrict_from(from_datetime) do
    restrict_from = Timex.shift(Timex.now(), days: restrict_from_in_days())
    Enum.max_by([from_datetime, restrict_from], &DateTime.to_unix/1)
  end

  defp required_san_stake_full_access() do
    Config.get(:required_san_stake_full_access) |> String.to_integer()
  end

  defp restrict_to_in_days() do
    -1 * (Config.get(:restrict_to_in_days) |> String.to_integer())
  end

  defp restrict_from_in_days do
    -1 * (Config.get(:restrict_from_in_days) |> String.to_integer())
  end
end
