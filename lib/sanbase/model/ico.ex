defmodule Sanbase.Model.Ico do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency


  schema "icos" do
    field :start_date, Ecto.Date
    field :end_date, Ecto.Date
    field :tokens_issued_at_ico, :integer
    field :tokens_sold_at_ico, :integer
    field :funds_raised_btc, :decimal
    field :usd_btc_icoend, :decimal
    field :usd_eth_icoend, :decimal
    field :minimal_cap_amount, :decimal
    field :maximal_cap_amount, :decimal
    belongs_to :project, Project
    belongs_to :cap_currency, Currency
    many_to_many :currencies, Currency, join_through: "ico_currencies", on_replace: :delete
  end

  @doc false
  def changeset(%Ico{} = ico, attrs \\ %{}) do
    ico
    |> cast(attrs, [:start_date, :end_date, :tokens_issued_at_ico, :tokens_sold_at_ico, :funds_raised_btc, :usd_btc_icoend, :usd_eth_icoend, :minimal_cap_amount, :maximal_cap_amount, :project_id, :cap_currency_id])
    |> validate_required([:project_id])
    |> unique_constraint(:project_id)
  end
end
