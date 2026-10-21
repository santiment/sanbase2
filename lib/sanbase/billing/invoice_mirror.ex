defmodule Sanbase.Billing.InvoiceMirror do
  @moduledoc ~s"""
  A local copy of every Stripe invoice and its lines, whatever paid it.

  Card payments are otherwise only sent to Kafka, and `stripe_credit_invoices` holds
  only the invoices settled from credit. Revenue, churn and renewal of business
  clients are derived from the invoice lines here: each line carries the plan, the
  period it pays for and the amount.

  `Sanbase.Billing.InvoiceMirror.Sync` fills the mirror - daily for the recent past,
  and by hand through `Sanbase.Billing.InvoiceMirror.SyncJob` for wider ranges. Every
  import is recorded as a `Sanbase.Billing.InvoiceMirror.SyncRun`, so a range nobody
  has imported shows up in `coverage/2` instead of looking like a range without
  revenue.
  """

  import Ecto.Query

  alias Sanbase.Billing.InvoiceMirror.SyncRun
  alias Sanbase.Repo

  @doc ~s"""
  When the last completed import finished, or `nil` when nothing has been imported.
  """
  @spec last_synced_at() :: DateTime.t() | nil
  def last_synced_at do
    case SyncRun.last_completed() do
      nil -> nil
      run -> run.updated_at
    end
  end

  @doc ~s"""
  The most recent imports, newest first, failed ones included.
  """
  @spec recent_runs(pos_integer()) :: [%SyncRun{}]
  def recent_runs(limit \\ 10), do: SyncRun.recent(limit)

  @doc ~s"""
  The part of `from_date .. to_date` that no completed import covers.

  Returns a list of `{from, to}` date tuples - empty when the range is fully imported.
  Coverage is computed one day at a time, which is precise enough for a range measured
  in months and keeps the gaps easy to state.

  A run covers its range only up to the day before it started: invoices created later
  on the day it ran were not there to import. So today is never covered, and callers
  ask for coverage through yesterday.
  """
  @spec coverage(Date.t(), Date.t()) :: [{Date.t(), Date.t()}]
  def coverage(%Date{} = from_date, %Date{} = to_date) do
    covered =
      from(r in SyncRun,
        where: r.status == "completed" and r.from_date <= ^to_date and r.to_date >= ^from_date,
        select: {r.from_date, r.to_date, r.inserted_at}
      )
      |> Repo.all()
      |> Enum.flat_map(&covered_days/1)
      |> MapSet.new()

    Date.range(from_date, to_date)
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> group_consecutive()
  end

  defp covered_days({from, to, started_at}) do
    last_full_day = started_at |> DateTime.to_date() |> Date.add(-1)
    to = Enum.min([to, last_full_day], Date)

    if Date.compare(to, from) == :lt, do: [], else: Date.range(from, to)
  end

  defp group_consecutive([]), do: []

  defp group_consecutive([first | rest]) do
    rest
    |> Enum.reduce([{first, first}], fn date, [{range_from, range_to} | acc] ->
      if Date.diff(date, range_to) == 1 do
        [{range_from, date} | acc]
      else
        [{date, date}, {range_from, range_to} | acc]
      end
    end)
    |> Enum.reverse()
  end
end
