defmodule Sanbase.Billing.Plan.Bundle.Price do
  @moduledoc ~s"""
  The local catalog of things a bundle customer can buy: one row per SKU per
  billing interval.

  ## Why this is not a `plans` row

  A `plans` row means "a whole subscription tier", and a great deal of existing
  code assumes exactly one of them per subscription - the upgrade/downgrade path
  most of all. Per-item prices modelled as plans would be picked up by that code
  and mishandled. Keeping them in their own table means none of it applies.

  ## Amounts may be missing

  `amount` is nullable and that is meaningful: the item is known and sellable in
  principle but has no agreed price yet. Nothing can be charged for a row with no
  amount, and `sellable/1` leaves those out.

  ## Changing a price

  Stripe Prices are immutable, so a price change is a new row plus deactivating
  the old one - never an update in place. The partial unique index allows any
  number of inactive rows per SKU and interval but only one active, so history is
  kept without ambiguity about the current price.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Billing.Plan.Bundle.ApiCallAddon
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Repo

  @intervals ["month", "year"]

  @type t :: %__MODULE__{
          id: integer(),
          sku: String.t(),
          type: :package | :api_calls,
          interval: String.t(),
          stripe_price_id: String.t() | nil,
          amount: integer() | nil,
          currency: String.t(),
          is_active: boolean()
        }

  schema "bundle_prices" do
    field(:sku, :string)
    field(:type, Ecto.Enum, values: [:package, :api_calls])
    field(:interval, :string)
    field(:stripe_price_id, :string)
    field(:amount, :integer)
    field(:currency, :string, default: "USD")
    field(:is_active, :boolean, default: true)

    timestamps()
  end

  @fields [:sku, :type, :interval, :stripe_price_id, :amount, :currency, :is_active]

  @doc ~s"""
  The billing intervals a bundle can be bought on. A cart may not mix them -
  Stripe bills one subscription on one interval.
  """
  @spec intervals() :: [String.t()]
  def intervals, do: @intervals

  @doc false
  def changeset(%__MODULE__{} = price, attrs) do
    price
    |> cast(attrs, @fields)
    |> validate_required([:sku, :type, :interval, :currency])
    |> validate_inclusion(:interval, @intervals)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_sku()
    |> unique_constraint(:stripe_price_id)
    |> unique_constraint([:sku, :interval],
      name: :bundle_prices_sku_interval_is_active_index,
      message: "already has an active price for this interval"
    )
  end

  @doc ~s"""
  Create a catalog row.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc ~s"""
  Every active row for the given interval.
  """
  @spec active(String.t()) :: [t()]
  def active(interval) when interval in @intervals do
    from(p in __MODULE__,
      where: p.is_active and p.interval == ^interval,
      order_by: [asc: p.type, asc: p.sku]
    )
    |> Repo.all()
  end

  @doc ~s"""
  Active rows that can actually be charged for - those with a decided amount and
  a Stripe price behind them.

  Everything else is catalog scaffolding: known to exist, not yet purchasable.
  """
  @spec sellable(String.t()) :: [t()]
  def sellable(interval) when interval in @intervals do
    from(p in __MODULE__,
      where:
        p.is_active and p.interval == ^interval and not is_nil(p.amount) and
          not is_nil(p.stripe_price_id),
      order_by: [asc: p.type, asc: p.sku]
    )
    |> Repo.all()
  end

  @doc ~s"""
  The catalog rows behind the given Stripe Price ids, keyed by Stripe Price id.

  What a Stripe Price id means - which SKU, which type, which interval - is the
  question every webhook about a bundle subscription has to answer, because
  Stripe reports prices and the local model records SKUs.

  ## Inactive rows are included, deliberately

  A price change deactivates the old row and inserts a new one (`replace/1`), but
  Stripe never re-prices an existing subscription item on its own: every
  subscription bought before the change keeps referencing the *old* Stripe Price
  forever. Filtering on `is_active` here would make all of those items look like
  unknown prices the moment a price is changed, and the reconciliation in
  `Sanbase.Billing.Plan.Bundle.ItemSync` would then refuse to maintain the
  subscriptions it exists to maintain - or, worse, read the missing SKU as a
  removed package. What a price id means is a historical fact and does not
  expire; `is_active` says only whether it may still be *sold*, which is
  `sellable/1`'s business.

  `stripe_price_id` is unique across the table, so each id maps to at most one
  row whether it is active or not.
  """
  @spec by_stripe_price_ids([String.t() | nil]) :: %{String.t() => t()}
  def by_stripe_price_ids(stripe_price_ids) when is_list(stripe_price_ids) do
    ids = stripe_price_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        from(p in __MODULE__, where: p.stripe_price_id in ^ids)
        |> Repo.all()
        |> Map.new(&{&1.stripe_price_id, &1})
    end
  end

  @doc ~s"""
  Replace a price: deactivate the current active row for this SKU and interval,
  then insert the new one. Stripe Prices are immutable, so this is the only
  correct shape for a price change.
  """
  @spec replace(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def replace(%{sku: sku, interval: interval} = attrs) do
    Repo.transaction(fn ->
      # NaiveDateTime, not DateTime - `timestamps()` maps to `timestamp without
      # time zone`, and update_all writes the term through without casting it to
      # the field's type the way a changeset would.
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      from(p in __MODULE__, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
      |> Repo.update_all(set: [is_active: false, updated_at: now])

      case create(attrs) do
        {:ok, price} -> price
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp validate_sku(changeset) do
    case {get_field(changeset, :type), get_field(changeset, :sku)} do
      # A missing SKU is validate_required's business. Reporting it here too would
      # add a second, less useful message about the wrong type.
      {_type, nil} -> changeset
      {:package, sku} -> known(changeset, Package.by_slug(sku))
      {:api_calls, sku} -> known(changeset, ApiCallAddon.calls_per_month(sku))
      _ -> changeset
    end
  end

  defp known(changeset, {:ok, _}), do: changeset
  defp known(changeset, {:error, message}), do: add_error(changeset, :sku, message)
end
