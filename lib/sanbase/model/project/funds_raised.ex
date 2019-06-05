defmodule Sanbase.Model.Project.FundsRaised do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, Ico, IcoCurrency, Currency}

  def ico_price(%Project{} = project) do
    ico_with_max_price =
      project
      |> Repo.preload([:icos])
      |> Map.get(:icos)
      |> Enum.reject(fn ico -> is_nil(ico.token_usd_ico_price) end)
      |> Enum.max_by(
        fn ico -> ico.token_usd_ico_price |> Decimal.to_float() end,
        fn -> nil end
      )

    case ico_with_max_price do
      %Ico{token_usd_ico_price: ico_price} ->
        ico_price |> Decimal.to_float()

      _ ->
        nil
    end
  end

  def initial_ico(%Project{id: id}) do
    Ico
    |> where([i], i.project_id == ^id)
    |> first(:start_date)
    |> Repo.one()
  end

  def funds_raised_usd_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_usd_ico_end_price/1)
  end

  def funds_raised_eth_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_eth_ico_end_price/1)
  end

  def funds_raised_btc_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_btc_ico_end_price/1)
  end

  defp funds_raised_ico_end_price(project, ico_funds_raised_fun) do
    Repo.preload(project, :icos).icos
    |> Enum.map(ico_funds_raised_fun)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end

  @doc """
  For every currency aggregates all amounts for every ICO of the given project
  """
  def funds_raised_icos(%Project{id: id}) do
    query =
      from(
        i in Ico,
        inner_join: ic in IcoCurrency,
        on: ic.ico_id == i.id and not is_nil(ic.amount),
        inner_join: c in Currency,
        on: c.id == ic.currency_id,
        where: i.project_id == ^id,
        group_by: c.code,
        order_by: fragment("case
                            			when ? = 'BTC' then '_'
                            			when ? = 'ETH' then '__'
                            			when ? = 'USD' then '___'
                            		  else ?
                            		end", c.code, c.code, c.code, c.code),
        select: %{currency_code: c.code, amount: sum(ic.amount)}
      )

    Repo.all(query)
  end
end
