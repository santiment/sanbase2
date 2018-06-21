defmodule SanbaseWeb.Graphql.Middlewares.ApiDelay do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  @required_san_stake_realtime_api 0

  def call(resolution, _) do
    args = resolution.definition.argument_data
    to_datetime = args |> Map.get(:to, nil)

    case to_datetime do
      nil ->
        resolution

      to_datetime ->
        put_in(resolution.definition.argument_data, %{to: dalay_1day(to_datetime)})
    end
  end

  defp has_enough_san_tokens?(current_user, san_tokens) do
    if Decimal.cmp(User.san_balance!(current_user), Decimal.new()) == :gt do
      true
    else
      {:error, "Insufficient SAN balance"}
    end
  end

  defp dalay_1day(to_datetime) do
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
