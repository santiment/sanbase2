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
    |> add_currencies(attrs)
  end

  def add_currencies(changeset, attrs) do
    if Enum.count(Map.get(attrs, :currencys, [])) > 0 do # deliberately is currencys - ex_admin puts that
      ids = attrs[:currencys]
      currencies = Sanbase.Repo.all(from c in Currency, where: c.id in ^ids)
      put_assoc(changeset, :currencies, currencies)
    else
      changeset
    end
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

    usd_btc = get_field(changeset, :usd_btc_icoend)
    usd_eth = get_field(changeset, :usd_eth_icoend)

    usd_change = calculate_usd_from_btc(btc_change, usd_change, usd_btc)
    usd_change = calculate_usd_from_eth(eth_change, usd_change, usd_eth)
    btc_change = calculate_btc_from_usd(usd_change, btc_change, usd_btc)
    eth_change = calculate_eth_from_usd(usd_change, eth_change, usd_eth)

    changeset
    |> add_change(:funds_raised_usd, usd_change)
    |> add_change(:funds_raised_btc, btc_change)
    |> add_change(:funds_raised_eth, eth_change)
  end

  defp add_change(changeset, key, {:ok, value}) do
    put_change(changeset, key, value)
  end

  defp add_change(changeset, key, :error) do
    changeset
  end

  defp calculate_usd_from_btc({:ok, btc}, :error, usd_btc) when not is_nil(btc) and not is_nil(usd_btc) do
    {:ok, Decimal.mult(btc,usd_btc)}
  end

  defp calculate_usd_from_btc(_btc, usd, _usd_btc), do: usd

  defp calculate_usd_from_eth({:ok, eth}, :error, usd_eth) when not is_nil(eth) and not is_nil(usd_eth) do
    {:ok, Decimal.mult(eth,usd_eth)}
  end

  defp calculate_usd_from_eth(_eth, usd, _usd_eth), do: usd

  defp calculate_btc_from_usd({:ok, usd}, :error, usd_btc) when not is_nil(usd) and not is_nil(usd_btc) do
    cond do
      !Decimal.equal?(usd_btc, Decimal.new(0)) ->
        {:ok, Decimal.div(usd,usd_btc)}
      true -> :error
    end
  end

  defp calculate_btc_from_usd(_usd, btc, _usd_btc), do: btc

  defp calculate_eth_from_usd({:ok, usd}, :error, usd_eth) when not is_nil(usd) and not is_nil(usd_eth) do
    cond do
      !Decimal.equal?(usd_eth, Decimal.new(0)) ->
        {:ok, Decimal.div(usd,usd_eth)}
      true -> :error
    end
  end

  defp calculate_eth_from_usd(_usd, eth, _usd_eth), do: eth
end
