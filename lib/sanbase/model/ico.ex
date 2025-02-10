defmodule Sanbase.Model.Ico do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Model.Currency
  alias Sanbase.Model.Ico
  alias Sanbase.Model.IcoCurrency
  alias Sanbase.Project
  alias Sanbase.Repo

  schema "icos" do
    belongs_to(:project, Project)
    field(:start_date, :date)
    field(:end_date, :date)
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
    has_many(:ico_currencies, IcoCurrency)
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

  def funds_raised_by_icos(ico_ids) when is_list(ico_ids) do
    Repo.all(
      from(i in __MODULE__,
        left_join: ic in assoc(i, :ico_currencies),
        inner_join: c in assoc(ic, :currency),
        where: i.id in ^ico_ids,
        select: %{ico_id: i.id, currency_code: c.code, amount: ic.amount}
      )
    )
  end

  def funds_raised_usd_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico) when not is_nil(end_date) do
    project = Project.by_id(project_id)

    funds_raised_ico_end_price_from_currencies(project, ico, "USD", end_date)
  end

  def funds_raised_usd_ico_end_price(_), do: nil

  def funds_raised_eth_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico) when not is_nil(end_date) do
    project = Project.by_id(project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "ETH", end_date)
  end

  def funds_raised_eth_ico_end_price(_), do: nil

  def funds_raised_btc_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico) when not is_nil(end_date) do
    project = Project.by_id(project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "BTC", end_date)
  end

  def funds_raised_btc_ico_end_price(_), do: nil

  # Private functions

  defp funds_raised_ico_end_price_from_currencies(_project, ico, target_currency, date) do
    datetime = Sanbase.DateTimeUtils.date_to_datetime(date)

    ico
    |> Repo.preload(ico_currencies: [:currency])
    |> Map.get(:ico_currencies, [])
    |> Enum.map(&get_funds_raised(&1, target_currency, datetime))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end

  defp get_funds_raised(ico_currency, target_currency, datetime) do
    case Project.by_currency(ico_currency.currency) do
      %Project{slug: slug} ->
        price =
          Sanbase.Price.Utils.fetch_last_price_before(
            slug,
            target_currency,
            datetime
          )

        price && ico_currency.amount &&
          price * Decimal.to_float(ico_currency.amount)

      _ ->
        nil
    end
  end
end
