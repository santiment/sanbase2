defmodule SanbaseWeb.Graphql.Middlewares.PostPaywallFilter do
  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  alias Sanbase.Insight.{Post, PostPaywall}
  alias Sanbase.Timeline.TimelineEvent

  def call(%Resolution{errors: [_ | _]} = resolution, _opts), do: resolution

  def call(
        %Resolution{value: value, context: context} = resolution,
        _opts
      )
      when not is_nil(value) do
    %{resolution | value: filter_value(value, context.auth[:current_user])}
  end

  def call(resolution, _), do: resolution

  # helpers
  defp filter_value(%Post{} = insight, current_user) do
    PostPaywall.maybe_filter_paywalled_insights([insight], current_user)
    |> hd()
  end

  defp filter_value([%Post{} | _rest] = insights, current_user) do
    PostPaywall.maybe_filter_paywalled_insights(insights, current_user)
  end

  defp filter_value(%TimelineEvent{} = event, current_user) do
    update_event_insight(event, current_user)
  end

  defp filter_value(%{events: [%TimelineEvent{} | _rest] = events} = timeline, current_user) do
    %{timeline | events: Enum.map(events, &update_event_insight(&1, current_user))}
  end

  defp filter_value(value, _), do: value

  defp update_event_insight(event, current_user) do
    Map.update(event, :post, nil, fn insight ->
      Sanbase.Insight.PostPaywall.maybe_filter_paywalled_insights([insight], current_user)
      |> hd()
    end)
  end
end
