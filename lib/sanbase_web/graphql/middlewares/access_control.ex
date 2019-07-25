defmodule SanbaseWeb.Graphql.Middlewares.AccessControl do
  @moduledoc """
  Module that currently checks whether current_user's plan has access to requested
  query and if not - returns error message to upgrade.
  If user is not logged in passes to next middleware TimeframeRestriction
  which restricts historical data usage to 90 days.
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Billing.{Subscription, Plan}

  require Logger

  @free_subscription Subscription.free_subscription()

  def call(
        %Resolution{
          definition: definition,
          context: %{
            auth: %{subscription: subscription}
          }
        } = resolution,
        _config
      )
      when not is_nil(subscription) do
    query = definition.name |> Macro.underscore() |> String.to_existing_atom()

    check_access_to_query(subscription, resolution, query)
  end

  def call(%Resolution{} = resolution, _), do: resolution

  # TODO: Leave this after staking is removed. To enable execution just delete
  # the previous call/2
  def call(%Resolution{definition: definition} = resolution, _) do
    query = definition.name |> Macro.underscore() |> String.to_existing_atom()
    check_access_to_query(@free_subscription, resolution, query)
  end

  defp check_access_to_query(nil, resolution, _), do: resolution

  defp check_access_to_query(subscription, resolution, query) do
    # Do not check mutations against the Subscription plan
    if Subscription.has_access?(subscription, query) do
      resolution
    else
      upgrade_message =
        Plan.lowest_plan_with_metric(query)
        |> upgrade_message(query)

      resolution
      |> Resolution.put_result({
        :error,
        """
        Requested metric #{query} is not provided by the current subscription plan #{
          Subscription.plan_name(subscription)
        }.
        #{upgrade_message}
        """
      })
    end
  end

  defp upgrade_message(nil, _), do: ""

  defp upgrade_message(plan_name, query) do
    "Please upgrade to #{plan_name |> Atom.to_string() |> String.capitalize()} or higher to get access to #{
      query
    }"
  end
end
