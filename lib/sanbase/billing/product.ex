defmodule Sanbase.Billing.Product do
  @moduledoc """
  Module for managing Sanbase products - objects that describe services
  a customer can subscribe to.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  # Sanbase API product id. Ids for products are fixed.
  @sanbase_api 1

  schema "products" do
    field(:name, :string)
    field(:stripe_id, :string)

    has_many(:plans, Plan)
  end

  def sanbase_api(), do: @sanbase_api

  def changeset(%__MODULE__{} = product, attrs \\ %{}) do
    product
    |> cast(attrs, [:name, :stripe_id])
  end

  def by_id(product_id) do
    Repo.get(__MODULE__, product_id)
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
