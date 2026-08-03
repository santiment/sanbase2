defmodule Sanbase.Billing.Plan.Bundle.Entitlement do
  @moduledoc ~s"""
  What a bundle subscription is entitled to: which metrics, queries and signals
  it may use, how many API calls it gets, and how far back its data goes.

  Stored as JSON on `subscriptions.bundle_entitlement`, worked out once when the
  subscription's items change rather than on every request. See
  `docs/composable-api-plans-handover.md` §5.3 and §5.4.

  `nil` for every subscription that is not a bundle, which today is all of them.

  ## Why the packages are kept alongside the access maps

  `packages` is not used to decide access - the access maps are. It is kept so
  that support and invoicing can answer "what did this customer buy?" without
  working backwards from a metric list.

  ## Versions

  `schema_version` marks the shape of this struct. If stored data was written by
  older code, re-work it out rather than trusting it.

  `package_snapshot_version` records which published definition of the packages
  was used. Two customers who bought "Market" months apart can hold different
  metric lists, which is intended: a customer keeps what they paid for until
  something deliberately re-works it out.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Billing.Plan.AccessMap

  @current_schema_version 1

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:packages, {:array, :string}, default: [])

    field(:metric_access, :map)
    field(:query_access, :map)
    field(:signal_access, :map)

    field(:api_call_limits, :map)

    field(:historical_data_in_days, :integer)
    field(:realtime_data_cut_off_in_days, :integer, default: 0)

    field(:package_snapshot_version, :integer)
    field(:schema_version, :integer, default: @current_schema_version)
  end

  @fields [
    :packages,
    :metric_access,
    :query_access,
    :signal_access,
    :api_call_limits,
    :historical_data_in_days,
    :realtime_data_cut_off_in_days,
    :package_snapshot_version,
    :schema_version
  ]

  # historical_data_in_days is deliberately optional: nil means "no limit", which
  # is what every bundle gets today (§5.7).
  @required_fields [
    :metric_access,
    :query_access,
    :signal_access,
    :api_call_limits,
    :schema_version
  ]

  def current_schema_version, do: @current_schema_version

  def changeset(%__MODULE__{} = entitlement, attrs) do
    entitlement
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_change(:api_call_limits, &validate_api_call_limits/2)
  end

  @doc ~s"""
  Whether stored data was written by a different version of this struct and
  should be worked out again rather than trusted.
  """
  @spec stale?(t :: %__MODULE__{} | nil) :: boolean()
  def stale?(nil), do: false
  def stale?(%__MODULE__{schema_version: version}), do: version != @current_schema_version

  @doc ~s"""
  Whether this entitlement allows a single metric, query or signal.

  Queries arrive as atoms from the GraphQL layer and are compared as strings,
  matching how the custom plan path does it.
  """
  @spec allows?(%__MODULE__{}, {:metric | :query | :signal, term()}) :: boolean()
  def allows?(%__MODULE__{} = entitlement, {:metric, metric}) do
    AccessMap.allows?(entitlement.metric_access, to_string(metric))
  end

  def allows?(%__MODULE__{} = entitlement, {:query, query}) do
    AccessMap.allows?(entitlement.query_access, to_string(query))
  end

  def allows?(%__MODULE__{} = entitlement, {:signal, signal}) do
    AccessMap.allows?(entitlement.signal_access, to_string(signal))
  end

  @doc ~s"""
  The API call limits in the atom-keyed shape the quota code expects.
  """
  @spec api_call_limits(%__MODULE__{}) :: %{month: integer(), hour: integer(), minute: integer()}
  def api_call_limits(%__MODULE__{api_call_limits: limits}) do
    %{
      month: Map.fetch!(limits, "month"),
      hour: Map.fetch!(limits, "hour"),
      minute: Map.fetch!(limits, "minute")
    }
  end

  # Same rule the custom plans use: month > hour > minute > 0. A quota that is
  # nil or out of order surfaces as an ArithmeticError several frames away
  # (api_call_limit.ex:478-496), so it is rejected on the way in.
  defp validate_api_call_limits(:api_call_limits, %{} = limits) do
    case limits do
      %{"minute" => minute, "hour" => hour, "month" => month}
      when is_integer(minute) and is_integer(hour) and is_integer(month) and
             month > hour and hour > minute and minute > 0 ->
        []

      _ ->
        [
          api_call_limits:
            "must be a map with integer month, hour and minute where month > hour > minute > 0"
        ]
    end
  end
end
