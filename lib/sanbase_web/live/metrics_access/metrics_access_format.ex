defmodule SanbaseWeb.MetricsAccessFormat do
  @moduledoc """
  Pure functions turning metric access values (days of history / lag, minimum
  plan) into the labels shown on the metrics access page.
  """

  alias Sanbase.Billing.Plan.PlanMetricAccess

  @type mode :: :relative | :exact

  @doc "Label for how far back the data is available."
  @spec history(non_neg_integer() | nil, mode(), Date.t()) :: String.t()
  def history(nil, _mode, _today), do: "Full history"

  def history(days, :exact, today) when is_integer(days) do
    "Since " <> Date.to_iso8601(Date.add(today, -days))
  end

  def history(days, :relative, _today) when is_integer(days) do
    cond do
      days > 0 and rem(days, 365) == 0 and div(days, 365) == 1 -> "Last year"
      days > 0 and rem(days, 365) == 0 -> "Last #{div(days, 365)} years"
      true -> "Last #{days} days"
    end
  end

  @doc "Label for how recent the data is."
  @spec lag(non_neg_integer() | nil, mode(), Date.t()) :: String.t()
  def lag(nil, _mode, _today), do: "Realtime"
  def lag(days, :relative, _today) when is_integer(days), do: "#{days}-day delay"

  def lag(days, :exact, today) when is_integer(days) do
    "Until " <> Date.to_iso8601(Date.add(today, -days))
  end

  @doc "Label for a metric locked in the selected plan. `nil` means no listed plan unlocks it."
  @spec locked(String.t() | nil) :: String.t()
  def locked(nil), do: "Custom plan only"

  def locked(plan_key) when is_binary(plan_key) do
    case Enum.find(PlanMetricAccess.plans(), &(&1.key == plan_key)) do
      %{label: label} -> "Requires #{label}"
      nil -> raise ArgumentError, "unknown plan key: #{inspect(plan_key)}"
    end
  end
end
