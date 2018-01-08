defmodule Sanbase.Model.Ico do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

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
    attrs = attrs
    |> ModelUtils.removeThousandsSeparator(:token_usd_ico_price)
    |> ModelUtils.removeThousandsSeparator(:token_eth_ico_price)
    |> ModelUtils.removeThousandsSeparator(:token_btc_ico_price)
    |> ModelUtils.removeThousandsSeparator(:tokens_issued_at_ico)
    |> ModelUtils.removeThousandsSeparator(:tokens_sold_at_ico)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_btc)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_usd)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_eth)
    |> ModelUtils.removeThousandsSeparator(:minimal_cap_amount)
    |> ModelUtils.removeThousandsSeparator(:maximal_cap_amount)

    ico
    |> changeset(attrs)
    |> cast_assoc(:ico_currencies, required: false, with: &IcoCurrencies.changeset_ex_admin/2)
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

  def funds_raised_usd_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Repo.get(Project, project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "USD", end_date)
  end

  def funds_raised_usd_ico_end_price(_), do: nil

  def funds_raised_eth_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Repo.get(Project, project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "ETH", end_date)
  end

  def funds_raised_eth_ico_end_price(_), do: nil

  def funds_raised_btc_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Repo.get(Project, project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "BTC", end_date)
  end

  def funds_raised_btc_ico_end_price(_), do: nil

  # Private functions

  defp funds_raised_ico_end_price_from_currencies(
         %Project{ticker: ticker, coinmarketcap_id: cmc_id},
         %Ico{} = ico,
         target_currency,
         date
       ) do
    timestamp = Sanbase.DateTimeUtils.ecto_date_to_datetime(date)

    Repo.preload(ico, ico_currencies: [:currency]).ico_currencies
    |> Enum.map(fn ic ->
      Sanbase.Prices.Utils.convert_amount(
        ic.amount,
        ic.currency.code,
        target_currency,
        timestamp
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end

  defp calculate_funds_raised(changeset) do
    btc_change = fetch_change(changeset, :funds_raised_btc)
    usd_change = fetch_change(changeset, :funds_raised_usd)
    eth_change = fetch_change(changeset, :funds_raised_eth)

    %{funds_raised_usd: funds_raised_usd_ico_end_price(ico),
      funds_raised_eth: funds_raised_eth_ico_end_price(ico),
      funds_raised_btc: funds_raised_btc_ico_end_price(ico)}
  end

  def funds_raised_usd_ico_end_price(%Ico{funds_raised_usd: nil, end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_impl("USD", "ETH", ico.funds_raised_eth, "BTC", ico.funds_raised_btc, end_date)
    |> case do
      nil -> funds_raised_ico_end_price_from_currencies(ico, "USD", end_date)
      funds_raised -> funds_raised
    end
  end
  def funds_raised_usd_ico_end_price(%Ico{funds_raised_usd: funds_raised_usd}), do: funds_raised_usd

  def funds_raised_eth_ico_end_price(%Ico{funds_raised_eth: nil, end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_impl("ETH", "USD", ico.funds_raised_usd, "BTC", ico.funds_raised_btc, end_date)
    |> case do
      nil -> funds_raised_ico_end_price_from_currencies(ico, "ETH", end_date)
      funds_raised -> funds_raised
    end
  end
  def funds_raised_eth_ico_end_price(%Ico{funds_raised_eth: funds_raised_eth}), do: funds_raised_eth

  def funds_raised_btc_ico_end_price(%Ico{funds_raised_btc: nil, end_date: end_date} = ico) when not is_nil(end_date) do
    funds_raised_ico_end_price_impl("BTC", "USD", ico.funds_raised_usd, "ETH", ico.funds_raised_eth, end_date)
    |> case do
      nil -> funds_raised_ico_end_price_from_currencies(ico, "BTC", end_date)
      funds_raised -> funds_raised
    end
  end
  def funds_raised_btc_ico_end_price(%Ico{funds_raised_btc: funds_raised_btc}), do: funds_raised_btc

  defp funds_raised_ico_end_price_impl(target_ticker, funds_raised_ticker1, funds_raised_amount1, funds_raised_ticker2, funds_raised_amount2, date) do
    timestamp = Sanbase.DateTimeUtils.ecto_date_to_datetime(date)

    Sanbase.Prices.Utils.convert_amount(funds_raised_amount1, funds_raised_ticker1, target_ticker, timestamp)
    |> case do
      nil -> Sanbase.Prices.Utils.convert_amount(funds_raised_amount2, funds_raised_ticker2, target_ticker, timestamp)
      converted_amount -> converted_amount
    end
  end

  defp funds_raised_ico_end_price_from_currencies(ico, target_ticker, date) do
    timestamp = Sanbase.DateTimeUtils.ecto_date_to_datetime(date)

    Repo.preload(ico, [ico_currencies: [:currency]]).ico_currencies
    |> Enum.reduce(nil, fn(ic, acc) ->
      Sanbase.Prices.Utils.convert_amount(ic.amount, ic.currency.code, target_ticker, timestamp)
      |> case do
        nil -> acc
        converted_amount ->
          case acc do
            nil -> converted_amount
            res -> Decimal.add(res, converted_amount)
          end
      end
    end)
  end
end
