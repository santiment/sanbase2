defmodule Sanbase.ExAdmin.Model.Ico do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.Project

  register_resource Sanbase.Model.Ico do
    query do
      %{all: [preload: [:project, :cap_currency, ico_currencies: [:currency]]]}
    end

    create_changeset(:changeset_ex_admin)
    update_changeset(:changeset_ex_admin)

    index do
      selectable_column()

      column(:id)
      column(:project)
      column(:start_date)
      column(:end_date)
      column(:tokens_issued_at_ico)
      # display the default actions column
      actions()
    end

    show ico do
      attributes_table()

      panel "Currency used and collected amount" do
        table_for ico.ico_currencies do
          column(:id, link: true)
          column(:currency)
          column(:amount)
        end
      end
    end

    form ico do
      inputs do
        input(
          ico,
          :project,
          collection: from(p in Project, order_by: p.name) |> Sanbase.Repo.all()
        )

        input(ico, :start_date)
        input(ico, :end_date)
        input(ico, :token_usd_ico_price)
        input(ico, :token_eth_ico_price)
        input(ico, :token_btc_ico_price)
        input(ico, :tokens_issued_at_ico)
        input(ico, :tokens_sold_at_ico)
        input(ico, :minimal_cap_amount)
        input(ico, :maximal_cap_amount)
        input(ico, :contract_block_number)
        input(ico, :contract_abi)
        input(ico, :comments)

        input(
          ico,
          :cap_currency,
          collection: from(c in Currency, order_by: c.code) |> Sanbase.Repo.all()
        )
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter(:set_defaults, only: [:new])
    end
  end

  def display_name(ico) do
    "#{ico.id}"
  end

  def set_defaults(conn, params, resource, :new) do
    resource =
      resource
      |> set_cap_currency_default()
      |> set_start_date_default()
      |> set_end_date_default()
      |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(%Ico{project_id: nil} = ico, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> ico
      project_id -> Map.put(ico, :project_id, project_id)
    end
  end

  defp set_cap_currency_default(%Ico{cap_currency_id: nil} = ico) do
    currency = Currency.get("ETH")

    case currency do
      %Currency{id: id} -> Map.put(ico, :cap_currency_id, id)
      _ -> ico
    end
  end

  defp set_cap_currency_default(%Ico{} = ico), do: ico

  defp set_start_date_default(%Ico{start_date: nil} = ico) do
    Map.put(ico, :start_date, Ecto.Date.utc())
  end

  defp set_start_date_default(%Ico{} = ico), do: ico

  defp set_end_date_default(%Ico{end_date: nil} = ico) do
    Map.put(ico, :end_date, Ecto.Date.utc())
  end

  defp set_end_date_default(%Ico{} = ico), do: ico
end
