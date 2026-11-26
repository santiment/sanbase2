defmodule Sanbase.Billing.Plan.PlanMetricAccess do
  @moduledoc """
  What a plan gets for a metric, per channel (Sanbase app or API).

  Everything is derived from the access checkers, so the answers match what is
  enforced on real requests.
  """

  alias Sanbase.Billing.Plan.{
    AccessChecker,
    ApiAccessChecker,
    SanbaseAccessChecker
  }

  @type plan_key :: String.t()
  @type channel :: :sanbase | :api
  @type access ::
          :free
          | {:window, history_days :: pos_integer() | nil, lag_days :: pos_integer() | nil}
          | {:locked, min_plan_key :: plan_key() | nil}

  @plans [
    %{key: "free", label: "Free", plan_name: "FREE", subscription_product: nil},
    %{
      key: "sanbase_pro",
      label: "Sanbase Pro",
      plan_name: "PRO",
      subscription_product: "SANBASE"
    },
    %{
      key: "sanbase_max",
      label: "Sanbase Max",
      plan_name: "MAX",
      subscription_product: "SANBASE"
    },
    %{
      key: "business_pro",
      label: "Business Pro",
      plan_name: "BUSINESS_PRO",
      subscription_product: "SANAPI"
    },
    %{
      key: "business_max",
      label: "Business Max",
      plan_name: "BUSINESS_MAX",
      subscription_product: "SANAPI"
    }
  ]

  @channels [
    %{key: :sanbase, label: "In Sanbase", product: "SANBASE"},
    %{key: :api, label: "Via API", product: "SANAPI"}
  ]

  @spec plans() :: [map()]
  def plans(), do: @plans

  @spec channels() :: [map()]
  def channels(), do: @channels

  @spec access({:metric, String.t()}, plan_key, channel) :: access
  def access({:metric, _} = query, plan_key, channel) do
    plan = plan!(plan_key)
    product = channel!(channel).product
    subscription_product = plan.subscription_product || product

    cond do
      not AccessChecker.restricted?(query) ->
        :free

      AccessChecker.plan_has_access?(query, product, plan.plan_name) ->
        history =
          AccessChecker.historical_data_in_days(
            query,
            product,
            subscription_product,
            plan.plan_name
          )

        lag =
          AccessChecker.realtime_data_cut_off_in_days(
            query,
            product,
            subscription_product,
            plan.plan_name
          )

        {:window, history, zero_to_nil(lag)}

      true ->
        {:locked, lowest_unlocking_plan(query, product)}
    end
  end

  @doc "The plan-level window, independent of any metric: `{history_days, lag_days}`."
  @spec headline(plan_key, channel) :: {pos_integer() | nil, pos_integer() | nil}
  def headline(plan_key, channel) do
    plan = plan!(plan_key)
    product = channel!(channel).product
    subscription_product = plan.subscription_product || product
    module = checker_module(channel)

    {
      module.historical_data_in_days(subscription_product, plan.plan_name),
      zero_to_nil(module.realtime_data_cut_off_in_days(subscription_product, plan.plan_name))
    }
  end

  defp checker_module(:sanbase), do: SanbaseAccessChecker
  defp checker_module(:api), do: ApiAccessChecker

  defp lowest_unlocking_plan(query, product) do
    Enum.find_value(@plans, fn plan ->
      if AccessChecker.plan_has_access?(query, product, plan.plan_name), do: plan.key
    end)
  end

  defp zero_to_nil(0), do: nil
  defp zero_to_nil(value), do: value

  defp plan!(key),
    do:
      Enum.find(@plans, &(&1.key == key)) || raise(ArgumentError, "unknown plan #{inspect(key)}")

  defp channel!(key),
    do:
      Enum.find(@channels, &(&1.key == key)) ||
        raise(ArgumentError, "unknown channel #{inspect(key)}")
end
