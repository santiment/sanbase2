defmodule Sanbase.Repo.Migrations.OrderSanbasePlans do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  def up do
    setup()

    order_list = [1, 101, 102, 5, 103, 104, 9, 2, 3, 4, 6, 7, 8]
    len = length(order_list)

    order_list
    |> Enum.with_index()
    |> Map.new(fn {item, idx} -> {item, len - idx} end)
    |> Enum.sort_by(fn {_, v} -> v end, &>=/2)
    |> Enum.each(fn {plan_id, order} ->
      Plan
      |> Repo.get(plan_id)
      |> Plan.changeset(%{order: order})
      |> Repo.update()
    end)
  end

  def down do
    execute("UPDATE plans SET order=0 where product_id = 1")
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:stripity_stripe)
  end
end
