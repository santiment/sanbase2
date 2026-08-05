defmodule Sanbase.Billing.Subscription.Item do
  @moduledoc ~s"""
  One purchased line item on a bundle subscription - a package, or a tier of
  extra API calls.

  A bundle is a single Stripe subscription with several items billed on one
  invoice, so `subscriptions.plan_id` cannot say what was bought. These rows can.

  Only bundle subscriptions have items. Every legacy subscription has none, which
  is how the two are told apart without asking Stripe.

  ## SKUs are validated against the definitions, not just the database

  `sku` is a plain string column, but a `:package` item must name a real package
  and an `:api_calls` item a real add-on tier. A typo would otherwise store fine
  and then silently contribute nothing when the entitlement is worked out - the
  customer would pay and receive less, with no error anywhere.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Billing.Plan.Bundle.ApiCallAddon
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo

  @type item_type :: :package | :api_calls

  @type t :: %__MODULE__{
          id: integer(),
          subscription_id: integer(),
          stripe_item_id: String.t() | nil,
          sku: String.t(),
          type: item_type(),
          quantity: pos_integer(),
          cancel_at_period_end: boolean()
        }

  schema "subscription_items" do
    field(:stripe_item_id, :string)
    field(:sku, :string)
    field(:type, Ecto.Enum, values: [:package, :api_calls])
    field(:quantity, :integer, default: 1)
    field(:cancel_at_period_end, :boolean, default: false)

    belongs_to(:subscription, Subscription)

    timestamps()
  end

  @fields [:subscription_id, :stripe_item_id, :sku, :type, :quantity, :cancel_at_period_end]

  @doc false
  def changeset(%__MODULE__{} = item, attrs) do
    item
    |> cast(attrs, @fields)
    |> validate_required([:subscription_id, :sku, :type, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_sku()
    |> unique_constraint([:subscription_id, :sku],
      name: :subscription_items_subscription_id_sku_index,
      message: "is already an item on this subscription"
    )
    |> unique_constraint(:stripe_item_id)
    |> foreign_key_constraint(:subscription_id)
  end

  @doc ~s"""
  All items on a subscription.
  """
  @spec by_subscription(integer()) :: [t()]
  def by_subscription(subscription_id) when is_integer(subscription_id) do
    from(i in __MODULE__, where: i.subscription_id == ^subscription_id, order_by: [asc: i.id])
    |> Repo.all()
  end

  @doc ~s"""
  Create an item.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  # A package quantity above one means nothing - you either own Market or you do
  # not - so it is rejected rather than silently ignored.
  defp validate_sku(changeset) do
    case {get_field(changeset, :type), get_field(changeset, :sku)} do
      # A missing SKU is validate_required's business. Reporting it here too would
      # add a second, less useful message about the wrong type.
      {_type, nil} ->
        changeset

      {:package, sku} ->
        changeset
        |> validate_known(:package, sku)
        |> validate_package_quantity()

      {:api_calls, sku} ->
        validate_known(changeset, :api_calls, sku)

      _ ->
        changeset
    end
  end

  defp validate_known(changeset, :package, sku) do
    case Package.by_slug(sku) do
      {:ok, _} -> changeset
      {:error, message} -> add_error(changeset, :sku, message)
    end
  end

  defp validate_known(changeset, :api_calls, sku) do
    case ApiCallAddon.calls_per_month(sku) do
      {:ok, _} -> changeset
      {:error, message} -> add_error(changeset, :sku, message)
    end
  end

  defp validate_package_quantity(changeset) do
    case get_field(changeset, :quantity) do
      1 -> changeset
      nil -> changeset
      _ -> add_error(changeset, :quantity, "must be 1 for a package item")
    end
  end
end
