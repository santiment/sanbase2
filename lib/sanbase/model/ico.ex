defmodule Sanbase.Model.Ico do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Model.ModelUtils
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrency

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

  @doc false
  def changeset_ex_admin(%Ico{} = ico, attrs \\ %{}) do
    attrs =
      attrs
      |> ModelUtils.remove_thousands_separator(:token_usd_ico_price)
      |> ModelUtils.remove_thousands_separator(:token_eth_ico_price)
      |> ModelUtils.remove_thousands_separator(:token_btc_ico_price)
      |> ModelUtils.remove_thousands_separator(:tokens_issued_at_ico)
      |> ModelUtils.remove_thousands_separator(:tokens_sold_at_ico)
      |> ModelUtils.remove_thousands_separator(:minimal_cap_amount)
      |> ModelUtils.remove_thousands_separator(:maximal_cap_amount)

    ico
    |> changeset(attrs)
    |> cast_assoc(:ico_currencies, required: false, with: &IcoCurrency.changeset_ex_admin/2)
  end

  def funds_raised_by_icos(ico_ids) when is_list(ico_ids) do
    from(
      i in __MODULE__,
      left_join: ic in assoc(i, :ico_currencies),
      inner_join: c in assoc(ic, :currency),
      where: i.id in ^ico_ids,
      select: %{ico_id: i.id, currency_code: c.code, amount: ic.amount}
    )
    |> Repo.all()
  end

  def funds_raised_usd_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Project.by_id(project_id)

    funds_raised_ico_end_price_from_currencies(project, ico, "USD", end_date)
  end

  def funds_raised_usd_ico_end_price(_), do: nil

  def funds_raised_eth_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Project.by_id(project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "ETH", end_date)
  end

  def funds_raised_eth_ico_end_price(_), do: nil

  def funds_raised_btc_ico_end_price(%Ico{end_date: end_date, project_id: project_id} = ico)
      when not is_nil(end_date) do
    project = Project.by_id(project_id)
    funds_raised_ico_end_price_from_currencies(project, ico, "BTC", end_date)
  end

  def funds_raised_btc_ico_end_price(_), do: nil

  # Private functions

  defp funds_raised_ico_end_price_from_currencies(
         project,
         %Ico{} = ico,
         target_currency,
         date
       ) do
    datetime = Sanbase.DateTimeUtils.ecto_date_to_datetime(date)

    Repo.preload(ico, ico_currencies: [:currency]).ico_currencies
    |> Enum.map(fn ic ->
      case Project.by_currency(ic.currency) do
        %Project{slug: slug} ->
          price =
            Sanbase.Price.Utils.fetch_last_price_before(
              slug,
              target_currency,
              datetime
            )

          case price != nil and ic.amount != nil do
            true ->
              price * Decimal.to_float(ic.amount)

            false ->
              nil
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end
end
