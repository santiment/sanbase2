defmodule Sanbase.Pricing.Product do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Pricing.Plan
  alias __MODULE__
  alias Sanbase.Repo

  schema "products" do
    field(:name, :string)
    field(:stripe_id, :string)

    has_many(:plans, Plan)
  end

  def changeset(%__MODULE__{} = product, attrs \\ %{}) do
    product
    |> cast(attrs, [:name, :stripe_id])
  end

  def by_id(product_id) do
    Repo.get(__MODULE__, product_id)
    |> update_stripe_id_if_not_present()
  end

  defp update_stripe_id_if_not_present(%__MODULE__{stripe_id: stripe_id} = product)
       when is_nil(stripe_id) do
    Sanbase.StripeApi.create_product(product)
    |> case do
      {:ok, stripe_product} ->
        update_product(product, %{stripe_id: stripe_product.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_stripe_id_if_not_present(%__MODULE__{stripe_id: stripe_id} = product)
       when is_binary(stripe_id) do
    {:ok, product}
  end

  defp update_product(product, params) do
    product
    |> changeset(params)
    |> Repo.update()
  end
end
