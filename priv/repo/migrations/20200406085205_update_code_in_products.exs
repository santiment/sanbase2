defmodule Sanbase.Repo.Migrations.UpdateCodeInProducts do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Billing.Product
  alias Sanbase.Repo

  @product_id_code_map %{
    1 => "SANAPI",
    2 => "SANBASE",
    4 => "SANDATA",
    5 => "SAN_EXCHANGE_WALLETS"
  }

  def up do
    setup()

    for {product_id, code} <- @product_id_code_map do
      product_id
      |> Product.by_id()
      |> Product.changeset(%{code: code})
      |> Repo.update!()
    end

    # remove Sansheets product - no longer used
    3 |> Product.by_id() |> Repo.delete()
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
