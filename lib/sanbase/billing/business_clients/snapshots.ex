defmodule Sanbase.Billing.BusinessClients.Snapshots do
  @moduledoc ~s"""
  Monthly snapshots of the Business Clients page: one `ClientSnapshot` per client and
  one `MetricsSnapshot` per month, taken on the first day of the month.

  The revenue numbers could be recomputed from the invoice mirror at any time, but the
  log state and the usage could not, and the settings may change - a snapshot keeps a
  month's numbers as they were reported. Snapshots are append-only: taking a month
  again writes nothing new.
  """

  alias Sanbase.Billing.BusinessClients.{ClientSnapshot, MetricsSnapshot, Report, Settings}
  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.Repo

  require Logger

  @doc ~s"""
  Entry point for the monthly scheduler: snapshots the current month.

  Skipped when the invoice mirror has a gap since the start of the previous month: the
  renewals of the month just ended would be missing, and a snapshot is never rewritten.
  Taking the month by hand with `take/1` once the gap is imported fills it in.
  """
  @spec run() :: :ok | {:error, :invoice_gap}
  def run do
    today = Date.utc_today()
    since = today |> Date.beginning_of_month() |> Date.shift(month: -1)

    case InvoiceMirror.coverage(since, Date.add(today, -1)) do
      [] ->
        {:ok, result} = take(today)

        Logger.info(
          "[BusinessClients.Snapshots] #{result.month}: #{result.clients} client rows, " <>
            "metrics #{if result.metrics, do: "written", else: "already present"}"
        )

        :ok

      gaps ->
        Logger.warning(
          "[BusinessClients.Snapshots] Skipped #{Date.beginning_of_month(today)}: no invoice " <>
            "import covers #{Enum.map_join(gaps, ", ", fn {from, to} -> "#{from}..#{to}" end)}"
        )

        {:error, :invoice_gap}
    end
  end

  @doc ~s"""
  Writes the client rows and the metrics row of `month` (any date in it; default the
  current month), as of its first day. Rows that already exist are left untouched.

  Returns `{:ok, %{month: Date, clients: rows inserted, metrics: inserted?}}`.
  """
  @spec take(Date.t()) ::
          {:ok, %{month: Date.t(), clients: non_neg_integer(), metrics: boolean()}}
  def take(month \\ Date.utc_today()) do
    month = Date.beginning_of_month(month)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    client_rows =
      [as_of: month]
      |> Report.list_clients()
      |> Enum.map(&%{month: month, user_id: &1.user_id, data: &1, inserted_at: now})

    {clients, _} =
      Repo.insert_all(ClientSnapshot, client_rows,
        on_conflict: :nothing,
        conflict_target: [:month, :user_id]
      )

    metrics = Report.metrics(as_of: month)

    {metrics_count, _} =
      Repo.insert_all(MetricsSnapshot, [%{month: month, data: metrics, inserted_at: now}],
        on_conflict: :nothing,
        conflict_target: [:month]
      )

    {:ok, %{month: month, clients: clients, metrics: metrics_count == 1}}
  end

  @doc ~s"""
  Turns a stored `MetricsSnapshot.data` (string keys, ISO dates, as it comes back from
  JSON) into the shape `Report.metrics/1` returns.
  """
  @spec metrics_from_data(map()) :: map()
  def metrics_from_data(data) do
    window = Map.get(data, "window", %{})

    %{
      as_of: to_date(data["as_of"]),
      window: %{from: to_date(window["from"]), to: to_date(window["to"])},
      client_count: data["client_count"],
      at_risk_count: data["at_risk_count"],
      retention_action_pct: data["retention_action_pct"],
      client_churn: pick(data["client_churn"], ~w(rate lost base)a),
      revenue_churn: pick(data["revenue_churn"], ~w(rate lost_mrr base_mrr expansion_mrr)a),
      client_renewal: pick(data["client_renewal"], ~w(rate renewed due)a),
      revenue_renewal: pick(data["revenue_renewal"], ~w(rate renewed_acv due_acv)a),
      settings: settings_from_data(Map.get(data, "settings", %{}))
    }
  end

  # The settings the snapshot was computed with; a key added since falls back to its
  # default.
  defp settings_from_data(stored) do
    Map.new(Settings.defaults(), fn {key, default} ->
      {key, Map.get(stored, Atom.to_string(key), default)}
    end)
  end

  defp pick(nil, keys), do: Map.new(keys, &{&1, nil})
  defp pick(map, keys), do: Map.new(keys, &{&1, Map.get(map, Atom.to_string(&1))})

  defp to_date(nil), do: nil
  defp to_date(%Date{} = date), do: date
  defp to_date(string) when is_binary(string), do: Date.from_iso8601!(string)
end
