defmodule SanbaseWeb.Graphql.Middlewares.ApiDelay do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Auth.User

  @required_san_stake_realtime_api 1

  def call(
        %Resolution{
          context: %{
            auth: %{auth_method: :user_token, current_user: current_user}
          },
          arguments: %{to: _to}
        } = resolution,
        _
      ) do
    unless has_enough_san_tokens?(current_user) do
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
    if Decimal.cmp(User.san_balance!(current_user), Decimal.new(@required_san_stake_realtime_api)) ==
         :gt do
      true
    else
      false
    end
  end

  defp delay_1day(to_datetime) do
    yesterday = yesterday()

    case DateTime.compare(to_datetime, yesterday) do
      :gt -> yesterday
      _ -> to_datetime
    end
  end

  defp yesterday() do
    Timex.shift(Timex.now(), days: -1)
  end
end
