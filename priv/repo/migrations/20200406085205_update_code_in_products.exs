defmodule Sanbase.Repo.Migrations.UpdateCodeInProducts do
  use Ecto.Migration

  alias Sanbase.Repo
  alias Sanbase.Billing.Product

  @product_id_code_map %{
    1 => "SANAPI",
    2 => "SANBASE",
    4 => "SANDATA",
    5 => "SAN_EXCHANGE_WALLETS"
  }

  def up do
    setup()

    for {product_id, code} <- @product_id_code_map do
      Product.by_id(product_id)
      |> Product.changeset(%{code: code})
      |> Repo.update!()
    end

    # remove Sansheets product - no longer used
    Product.by_id(3) |> Repo.delete()
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
