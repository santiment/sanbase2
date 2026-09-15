defmodule Sanbase.Billing.CreditPayments.SyncRun do
  @moduledoc ~s"""
  A record of one import of credit payments from Stripe.

  Kept so that a range nobody has imported is visibly missing rather than looking like
  a range with no credit payments in it - the difference matters when the numbers are
  used to report revenue.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "stripe_credit_sync_runs" do
    field(:from_date, :date)
    field(:to_date, :date)
    field(:status, :string, default: "running")
    field(:invoices_upserted, :integer, default: 0)
    field(:grants_upserted, :integer, default: 0)
    field(:customers_scanned, :integer, default: 0)
    field(:duration_ms, :integer)
    field(:error_message, :string)

    belongs_to(:user, Sanbase.Accounts.User, foreign_key: :triggered_by)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(from_date to_date status invoices_upserted grants_upserted customers_scanned
             duration_ms error_message triggered_by)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required([:from_date, :to_date, :status])
  end

  def create(attrs) do
    %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  end

  def update(%__MODULE__{} = run, attrs) do
    run |> changeset(attrs) |> Repo.update()
  end

  @doc ~s"""
  The most recent runs, newest first.
  """
  def recent(limit \\ 10) do
    from(r in __MODULE__, order_by: [desc: r.id], limit: ^limit)
    |> Repo.all()
  end

  @doc ~s"""
  The last run that completed, or `nil` when nothing has ever been imported.
  """
  def last_completed do
    from(r in __MODULE__, where: r.status == "completed", order_by: [desc: r.id], limit: 1)
    |> Repo.one()
  end

  @doc ~s"""
  The part of `from_date .. to_date` that no completed run covers.

  Returns a list of `{from, to}` date tuples - empty when the range is fully imported.
  Coverage is computed one day at a time, which is precise enough for a range measured
  in months and keeps the gaps easy to state.
  """
  def gaps(%Date{} = from_date, %Date{} = to_date) do
    covered =
      from(r in __MODULE__,
        where: r.status == "completed" and r.from_date <= ^to_date and r.to_date >= ^from_date,
        select: {r.from_date, r.to_date}
      )
      |> Repo.all()
      |> Enum.flat_map(fn {from, to} -> Date.range(from, to) end)
      |> MapSet.new()

    Date.range(from_date, to_date)
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> group_consecutive()
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
