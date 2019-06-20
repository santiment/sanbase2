defmodule SanbaseWeb.Graphql.Middlewares.AccessControl do
  @moduledoc """
  Module that currently checks whether current_user's plan has access to requested
  query and if not - returns error message to upgrade.
  If user is not logged in passes to next middleware TimeframeRestriction
  which restricts historical data usage to 90 days.
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Pricing.{Subscription, Plan}

  require Logger

  @api_product_id 1

  def call(
        %Resolution{
          definition: definition,
          context: %{
            auth: %{current_user: current_user}
          }
        } = resolution,
        _config
      ) do
    query = definition.name |> Macro.underscore()

    current_user
    |> Subscription.current_subscription(@api_product_id)
    |> check_access_to_query(resolution, query)
  end

  def call(resolution, _), do: resolution

  defp check_access_to_query(nil, resolution, _), do: resolution

  defp check_access_to_query(current_subscription, resolution, query) do
    if Subscription.has_access?(current_subscription, query) do
      resolution
    else
      upgrade_message =
        Plan.plans_with_metric(query)
        |> upgrade_message(query)

      resolution
      |> Resolution.put_result({
        :error,
        """
        Requested metric #{query} is not provided by the current subscription plan #{
          Subscription.plan_name(current_subscription)
        }.
        #{upgrade_message}
        """
      })
    end
  end

  defp upgrade_message([], _), do: ""

  defp upgrade_message(plan_names, query) when is_list(plan_names) do
    "Please upgrade to #{plan_names |> Enum.join(" or ")} to get access to #{query}"
  end
end
