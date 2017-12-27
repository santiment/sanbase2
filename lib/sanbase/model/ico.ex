defmodule Sanbase.Model.Ico do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Sanbase.Model.ModelUtils
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies


  schema "icos" do
    belongs_to :project, Project
    field :start_date, Ecto.Date
    field :end_date, Ecto.Date
    field :tokens_issued_at_ico, :decimal
    field :tokens_sold_at_ico, :decimal
    field :funds_raised_btc, :decimal
    field :funds_raised_usd, :decimal
    field :funds_raised_eth, :decimal
    field :usd_btc_icoend, :decimal #TODO: can be fetched from external services
    field :usd_eth_icoend, :decimal #TODO: can be fetched from external services
    field :minimal_cap_amount, :decimal
    field :maximal_cap_amount, :decimal
    field :main_contract_address, :string
    field :contract_block_number, :integer
    field :contract_abi, :string
    field :comments, :string
    belongs_to :cap_currency, Currency, on_replace: :nilify
    has_many :ico_currencies, IcoCurrencies
  end

  @doc false
  def changeset(%Ico{} = ico, attrs \\ %{}) do
    ico
    |> cast(attrs, [:start_date, :end_date, :tokens_issued_at_ico, :tokens_sold_at_ico, :funds_raised_btc, :funds_raised_usd, :funds_raised_eth, :usd_btc_icoend, :usd_eth_icoend, :minimal_cap_amount, :maximal_cap_amount, :main_contract_address, :comments, :project_id, :cap_currency_id, :contract_block_number, :contract_abi])
    |> calculate_funds_raised()
    |> validate_required([:project_id])
  end

  @doc false
  def changeset_ex_admin(%Ico{} = ico, attrs \\ %{}) do
    attrs = attrs
    |> ModelUtils.removeThousandsSeparator(:tokens_issued_at_ico)
    |> ModelUtils.removeThousandsSeparator(:tokens_sold_at_ico)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_btc)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_usd)
    |> ModelUtils.removeThousandsSeparator(:funds_raised_eth)
    |> ModelUtils.removeThousandsSeparator(:usd_btc_icoend)
    |> ModelUtils.removeThousandsSeparator(:usd_eth_icoend)
    |> ModelUtils.removeThousandsSeparator(:minimal_cap_amount)
    |> ModelUtils.removeThousandsSeparator(:maximal_cap_amount)

    ico
    |> changeset(attrs)
    |> cast_assoc(:ico_currencies, required: false, with: &IcoCurrencies.changeset_ex_admin/2)
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
