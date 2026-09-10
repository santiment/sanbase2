defmodule Sanbase.Billing.Subscription.Grant do
  @moduledoc ~s"""
  An add-on sold by sales and applied by hand: extra monthly API calls, and full
  history on individual data packages.

  Stored as JSON on `subscriptions.grant`. See §8 task **GR** of
  `docs/composable-api-plans-handover.md`.

  ## Additive, never subtractive

  A grant can only raise what the plan already gives. That is not a convention -
  it is enforced where the grant is applied, and it is what makes a grant safe to
  write without reasoning about how it interacts with the plan it sits on. There
  is deliberately no way to express "fewer calls" or "less history".

  ## Why the metric list is frozen here

  `full_history_packages` says what was bought; `full_history_metrics` is that
  list expanded against the package snapshot at the moment of the grant. The
  expansion is stored so an access check is a membership test rather than a
  reverse lookup from metric to category on every request - the same trade a
  bundle entitlement makes with `metric_access`.

  It also means a grant goes stale by design: a metric added to Market next month
  is not covered until someone re-expands. That matches how the rest of this
  epic treats a purchase - a customer keeps what they paid for until something
  deliberately re-resolves them - and `package_snapshot_version` is what makes
  the staleness visible.

  ## `nil` cannot mean "no override"

  Everywhere else in this codebase `historical_data_in_days: nil` means
  *unlimited*. So a grant says which packages are upgraded and nothing else: the
  absence of a package from `full_history_packages` is the only way to say
  "leave this one alone". There is no day count to get wrong.

  ## No expiry

  A grant persists until an admin removes it. Product's decision (2026-09-10):
  the add-on is charged as a one-off invoice raised outside the subscription, and
  nothing ends the grant automatically. `granted_by_id` and `granted_at` are what
  keep it auditable.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Billing.Plan.Bundle.Package

  @type t :: %__MODULE__{}

  @all_packages "all"

  @primary_key false
  embedded_schema do
    field(:extra_api_calls_per_month, :integer, default: 0)

    field(:full_history_packages, {:array, :string}, default: [])
    field(:full_history_metrics, {:array, :string}, default: [])
    field(:package_snapshot_version, :integer)

    field(:note, :string)
    field(:granted_by_id, :integer)
    field(:granted_at, :utc_datetime)
  end

  @fields [
    :extra_api_calls_per_month,
    :full_history_packages,
    :full_history_metrics,
    :package_snapshot_version,
    :note,
    :granted_by_id,
    :granted_at
  ]

  @doc ~s"""
  The slug that means "every package", for a customer who upgraded the lot.

  Stored explicitly rather than as the five slugs so that re-expanding such a
  grant picks up a package added later, which is the one case where a customer
  clearly did buy "all of it" rather than a list that happened to be complete.
  """
  @spec all_packages() :: String.t()
  def all_packages, do: @all_packages

  def changeset(%__MODULE__{} = grant, attrs) do
    grant
    |> cast(attrs, @fields)
    |> validate_required([:note, :granted_at])
    |> validate_number(:extra_api_calls_per_month, greater_than_or_equal_to: 0)
    |> validate_change(:full_history_packages, &validate_packages/2)
    |> validate_not_empty()
  end

  @doc ~s"""
  Whether this grant upgrades the given metric to full history.

  Answered from the frozen metric list, so it costs a membership test and never
  reads the package snapshot. `"all"` short-circuits: a customer who upgraded
  every package gets full history on anything they can see, including metrics
  added since the grant was written.
  """
  @spec full_history?(t() | nil, String.t() | atom()) :: boolean()
  def full_history?(nil, _metric), do: false

  def full_history?(%__MODULE__{} = grant, metric) when is_binary(metric) do
    %__MODULE__{full_history_packages: packages, full_history_metrics: metrics} = grant

    @all_packages in (packages || []) or metric in (metrics || [])
  end

  def full_history?(%__MODULE__{} = grant, metric),
    do: full_history?(grant, to_string(metric))

  @doc ~s"""
  How many extra monthly API calls this grant adds. Zero when there is none.
  """
  @spec extra_api_calls(t() | nil) :: non_neg_integer()
  def extra_api_calls(nil), do: 0

  def extra_api_calls(%__MODULE__{extra_api_calls_per_month: calls}) when is_integer(calls),
    do: max(calls, 0)

  def extra_api_calls(%__MODULE__{}), do: 0

  # A grant that grants nothing is always a mistake - either a form submitted
  # empty or a removal that should have cleared the whole embed. Storing it would
  # leave a row that reads as an add-on while changing nothing.
  defp validate_not_empty(changeset) do
    calls = get_field(changeset, :extra_api_calls_per_month) || 0
    packages = get_field(changeset, :full_history_packages) || []

    if calls == 0 and packages == [] do
      add_error(
        changeset,
        :extra_api_calls_per_month,
        "a grant must add extra API calls, full history on at least one package, or both"
      )
    else
      changeset
    end
  end

  defp validate_packages(:full_history_packages, packages) when is_list(packages) do
    known = [@all_packages | Package.slugs()]

    case Enum.reject(packages, &(&1 in known)) do
      [] -> []
      unknown -> [full_history_packages: "unknown packages: #{Enum.join(unknown, ", ")}"]
    end
  end

  defp validate_packages(:full_history_packages, _), do: [full_history_packages: "must be a list"]
end
