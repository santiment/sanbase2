defmodule Sanbase.Model.Prices do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Prices
  alias Sanbase.Model.Project


  schema "prices" do
    field :price_btc, :decimal
    field :price_eth, :decimal
    field :price_usd, :decimal
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Prices{} = prices, attrs \\ %{}) do
    prices
    |> cast(attrs, [:price_usd, :price_btc, :price_eth])
    |> validate_required([:price_usd, :price_btc, :price_eth])
    |> unique_constraint(:project_id)
  end
end
