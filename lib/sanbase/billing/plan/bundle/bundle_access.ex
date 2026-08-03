defmodule Sanbase.Billing.Plan.Bundle.Access do
  @moduledoc ~s"""
  Answers access and quota questions for a bundle subscription, reading the
  entitlement stored on the subscription row.

  The counterpart of `Sanbase.Billing.Plan.CustomPlan.Access` for bundles, with
  one important difference. Custom plans are looked up **by name**, because a
  custom plan's name identifies one customer. Every bundle shares the single name
  `BUNDLE`, so the name identifies nothing and the entitlement has to be handed
  in. See §5.8 of docs/composable-api-plans-handover.md.

  ## A missing entitlement raises

  Every function here refuses a `nil` entitlement instead of falling back to
  anything. The alternative would be answering from the standard plan ladder,
  which cannot express packages and would quietly give a paying customer roughly
  free-tier access with no error anywhere - the worst failure mode in §7.5.
  Failing loudly is the only safe choice.
  """

  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.Entitlement

  @doc ~s"""
  Whether the bundle may use this metric, query or signal.
  """
  @spec plan_has_access?({:metric | :query | :signal, term()}, Entitlement.t() | nil) :: boolean()
  def plan_has_access?(query_or_argument, entitlement) do
    entitlement
    |> require_entitlement!(:plan_has_access?)
    |> Entitlement.allows?(query_or_argument)
  end

  @doc ~s"""
  The bundle's API call limits, keyed by `:month`, `:hour` and `:minute`.
  """
  @spec api_call_limits(Entitlement.t() | nil) :: %{
          month: integer(),
          hour: integer(),
          minute: integer()
        }
  def api_call_limits(entitlement) do
    entitlement
    |> require_entitlement!(:api_call_limits)
    |> Entitlement.api_call_limits()
  end

  @doc ~s"""
  How many days of history the bundle can read. `nil` means no limit, which is
  what every bundle gets today (§5.7).
  """
  @spec historical_data_in_days(Entitlement.t() | nil) :: non_neg_integer() | nil
  def historical_data_in_days(entitlement) do
    require_entitlement!(entitlement, :historical_data_in_days).historical_data_in_days
  end

  @doc ~s"""
  How close to now the bundle can read. `0` means realtime.
  """
  @spec realtime_data_cut_off_in_days(Entitlement.t() | nil) :: non_neg_integer() | nil
  def realtime_data_cut_off_in_days(entitlement) do
    require_entitlement!(entitlement, :realtime_data_cut_off_in_days).realtime_data_cut_off_in_days
  end

  defp require_entitlement!(%Entitlement{} = entitlement, _site), do: entitlement

  defp require_entitlement!(nil, site) do
    Bundle.missing_entitlement!(site)
  end
end
