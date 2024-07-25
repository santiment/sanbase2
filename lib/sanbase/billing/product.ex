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

  @code_product_id_map %{
    "SANAPI" => 1,
    "SANBASE" => 2
  }
  @product_atom_names Enum.map(@code_product_id_map, fn {k, _v} ->
                        k |> String.downcase() |> String.to_atom()
                      end)

  @product_code_by_id_map Enum.into(@code_product_id_map, %{}, fn {k, v} -> {v, k} end)

  schema "products" do
    field(:name, :string)
    field(:stripe_id, :string)
    field(:code, :string)

    has_many(:plans, Plan, on_delete: :delete_all)
  end

  def product_api(), do: @product_api
  def product_sanbase(), do: @product_sanbase

  def product_atom_names(), do: @product_atom_names

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
    Map.get(@product_code_by_id_map, id)
  end

  def id_by_code(code) when is_atom(code) and not is_nil(code) do
    code |> Atom.to_string() |> String.upcase() |> id_by_code()
  end

  def id_by_code(code) do
    Map.get(@code_product_id_map, code)
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
