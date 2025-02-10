defmodule Sanbase.Repo.Migrations.UpdateApiAndSandataProductNames do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Billing.Product
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    Enum.each(
      %{
        Product.product_api() => "SanAPI by Santiment",
        Product.product_sandata() => "Sandata by Santiment"
      },
      fn {id, new_name} ->
        Product
        |> Repo.get(id)
        |> Product.changeset(%{name: new_name})
        |> Repo.update!()
      end
    )
  end

  def down do
    :ok
  end
end
