defmodule SanbaseWeb.Graphql.Middlewares.AccessControl do
  @moduledoc """

  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Pricing.{Subscription, Plan}

  require Logger

  def call(
        %Resolution{
          definition: definition,
          context: %{
            auth: %{auth_method: :apikey, current_user: user}
          }
        } = resolution,
        _config
      ) do
    query = definition.name |> Macro.underscore()

    user
    |> Subscription.current_subscription()
    |> check_access_to_query(resolution, query)
  end

  def call(resolution, _), do: resolution

  defp check_access_to_query(nil, resolution, _), do: resolution

  defp check_access_to_query(current_subscription, resolution, query) do
    if Subscription.has_access?(current_subscription, query) do
      resolution
    else
      resolution
      |> Resolution.put_result({
        :error,
        """
        Requested metric #{query} is not provided by the current subscription plan #{
          Subscription.plan_name(current_subscription)
        }.
        Please upgrade to #{Plan.upgrade_plan(current_subscription.plan)} to get access to #{
          query
        }
        """
      })
    end
  end
end
