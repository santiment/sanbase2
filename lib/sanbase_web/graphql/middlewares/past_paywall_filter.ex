defmodule SanbaseWeb.Graphql.Middlewares.PostPaywallFilter do
  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  Sanbase.Insight.PostPaywall

  def call(%Resolution{errors: errors} = resolution, _opts) when errors != [], do: resolution

  def call(
        %Resolution{value: value, context: context} = resolution,
        _opts
      )
      when not is_nil(value) do
    filtered_value =
      Sanbase.Insight.PostPaywall.maybe_filter_paywalled(value, context.auth[:current_user])

    %{resolution | value: filtered_value}
  end

  def call(resolution, _), do: resolution
end
