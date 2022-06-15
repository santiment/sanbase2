defmodule Sanbase.Repo.Migrations.UpdateProductsNames do
  use Ecto.Migration
  alias Sanbase.Repo

  alias Sanbase.Billing.Product

  def up do
    Application.ensure_all_started(:tzdata)

    %{
      Product.product_api() => "Neuro by Santiment",
      Product.product_sanbase() => "Sanbase by Santiment",
      Product.product_sandata() => "Sandata by Santiment"
    }
    |> Enum.each(fn {id, new_name} ->
      Repo.get(Product, id)
      |> Product.changeset(%{name: new_name})
      |> Repo.update!()
    end)
  end

  def down do
    :ok
  end
end
