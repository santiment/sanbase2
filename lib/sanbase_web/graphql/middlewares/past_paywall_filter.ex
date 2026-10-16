defmodule SanbaseWeb.Graphql.Middlewares.PostPaywallFilter do
  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  alias Sanbase.Insight.{Post, PostPaywall}

  def call(%Resolution{errors: [_ | _]} = resolution, _opts), do: resolution

  def call(
        %Resolution{value: value, context: context} = resolution,
        _opts
      )
      when not is_nil(value) do
    %{resolution | value: filter_value(value, context.auth)}
  end

  def call(resolution, _), do: resolution

  # helpers
  defp filter_value(%Post{} = insight, auth) do
    PostPaywall.maybe_filter_paywalled([insight], auth) |> hd()
  end

  defp filter_value([%Post{} | _rest] = insights, auth) do
    PostPaywall.maybe_filter_paywalled(insights, auth)
  end

  defp filter_value(value, _), do: value
end
