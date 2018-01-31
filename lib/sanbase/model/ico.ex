defmodule Sanbase.Model.Ico do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo
  alias Sanbase.Model.ModelUtils
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies

  schema "icos" do
    belongs_to(:project, Project)
    field(:start_date, Ecto.Date)
    field(:end_date, Ecto.Date)
    field(:token_usd_ico_price, :decimal)
    field(:token_eth_ico_price, :decimal)
    field(:token_btc_ico_price, :decimal)
    field(:tokens_issued_at_ico, :decimal)
    field(:tokens_sold_at_ico, :decimal)
    field(:minimal_cap_amount, :decimal)
    field(:maximal_cap_amount, :decimal)
    field(:main_contract_address, :string)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
    field(:comments, :string)
    belongs_to(:cap_currency, Currency, on_replace: :nilify)
    has_many(:ico_currencies, IcoCurrencies)
  end

  @doc false
  def changeset(%Ico{} = ico, attrs \\ %{}) do
    ico
    |> cast(attrs, [
      :start_date,
      :end_date,
      :tokens_issued_at_ico,
      :tokens_sold_at_ico,
      :minimal_cap_amount,
      :maximal_cap_amount,
      :main_contract_address,
      :comments,
      :project_id,
      :cap_currency_id,
      :contract_block_number,
      :contract_abi,
      :token_usd_ico_price,
      :token_eth_ico_price,
      :token_btc_ico_price
    ])
    |> validate_required([:project_id])
  end

  @doc false
  def changeset_ex_admin(%Ico{} = ico, attrs \\ %{}) do
    attrs =
      attrs
      |> ModelUtils.removeThousandsSeparator(:token_usd_ico_price)
      |> ModelUtils.removeThousandsSeparator(:token_eth_ico_price)
      |> ModelUtils.removeThousandsSeparator(:token_btc_ico_price)
      |> ModelUtils.removeThousandsSeparator(:tokens_issued_at_ico)
      |> ModelUtils.removeThousandsSeparator(:tokens_sold_at_ico)
      |> ModelUtils.removeThousandsSeparator(:minimal_cap_amount)
      |> ModelUtils.removeThousandsSeparator(:maximal_cap_amount)

    ico
    |> changeset(attrs)
    |> cast_assoc(:ico_currencies, required: false, with: &IcoCurrencies.changeset_ex_admin/2)
  end

  def funds_raised_usd_ico_end_price(%Ico{end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_from_currencies(ico, "USD", end_date)
  end

  def funds_raised_eth_ico_end_price(%Ico{end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_from_currencies(ico, "ETH", end_date)
  end

  def funds_raised_btc_ico_end_price(%Ico{end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_from_currencies(ico, "BTC", end_date)
  end

  defp funds_raised_ico_end_price_from_currencies(ico, target_ticker, date) do
    timestamp = Sanbase.DateTimeUtils.ecto_date_to_datetime(date)

    Repo.preload(ico, ico_currencies: [:currency]).ico_currencies
    |> Enum.map(fn ic ->
      Sanbase.Prices.Utils.convert_amount(ic.amount, ic.currency.code, target_ticker, timestamp)
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
    end
  end
end
