defmodule Sanbase.Repo.Migrations.RescrapePricesSinceBeginningOfAugust do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Prices.Store

  def up, do: ok

  def down, do: :ok
end
