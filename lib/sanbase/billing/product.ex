defmodule Sanbase.Billing.Product do
  @moduledoc """
  Module for managing Sanbase products - objects that describe services
  a customer can subscribe to.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  @type product_id :: non_neg_integer()

  # Sanbase API product id. Ids for products are fixed.
  @product_api 1
  @product_sanbase 2
  @product_sandata 4
  @product_exchange_wallets 5

  schema "products" do
    field(:name, :string)
    field(:stripe_id, :string)
    field(:code, :string)

    has_many(:plans, Plan, on_delete: :delete_all)
  end

  def product_api(), do: @product_api
  def product_sanbase(), do: @product_sanbase
  def product_sandata(), do: @product_sandata
  def product_exchange_wallets(), do: @product_exchange_wallets

  def changeset(%__MODULE__{} = product, attrs \\ %{}) do
    product
    |> cast(attrs, [:name, :code, :stripe_id])
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def by_code(code) do
    Repo.get_by(__MODULE__, code: code)
  end

  def code_by_id(id) do
    Repo.get(__MODULE__, id).code
  end

  @doc """
  If product does not have `stripe_id` - create a product in Stripe and update with
  received `stripe_id`.
  """
  def maybe_create_product_in_stripe(%__MODULE__{stripe_id: stripe_id} = product)
      when is_nil(stripe_id) do
    Sanbase.StripeApi.create_product(product)
    |> case do
      {:ok, stripe_product} ->
        update_product(product, %{stripe_id: stripe_product.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def maybe_create_product_in_stripe(%__MODULE__{stripe_id: stripe_id} = product)
      when is_binary(stripe_id) do
    {:ok, product}
  end

  defp update_product(product, params) do
    product
    |> changeset(params)
    |> Repo.update()
  end
end
