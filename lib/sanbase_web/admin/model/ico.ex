defmodule Sanbase.ExAdmin.Model.Ico do
  use ExAdmin.Register

  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.Project

  register_resource Sanbase.Model.Ico do

    query do
      %{all: [preload: [:project, :cap_currency, ico_currencies: [:currency]]] }
    end

    create_changeset :changeset_ex_admin
    update_changeset :changeset_ex_admin

    form ico do
      inputs do
        input ico, :project, collection: Sanbase.Repo.all(Project)
        input ico, :start_date
        input ico, :end_date
        input ico, :tokens_issued_at_ico
        input ico, :tokens_sold_at_ico
        input ico, :funds_raised_btc
        input ico, :funds_raised_usd
        input ico, :funds_raised_eth
        input ico, :usd_btc_icoend
        input ico, :usd_eth_icoend
        input ico, :minimal_cap_amount
        input ico, :maximal_cap_amount
        input ico, :main_contract_address
        input ico, :comments
        input ico, :cap_currency, collection: Sanbase.Repo.all(Currency)
      end

      inputs "Ico Currencies" do
        has_many ico, :ico_currencies, fn(c) ->
          inputs :currency, collection: Sanbase.Repo.all(Currency)
          input c, :amount
        end
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter :set_defaults, only: [:new]
    end

    # We want to add project name to the filters on the index page
    # ex_admin has limited support for modifying the filter, so we use a little hackery:
    # 1. We inject a textfield in the filter form for "project_name" (Can't add it to the ecto schema as ex_admin doesn't display virtual fields)
    # 2. On submit of the filter form it GET-s the index page with a query parameter "project_name", which we use to filter the ecto query
    #   * Looking at the code in ExAdmin.AdminResourceController.index() and ExAdmin.Register.run_query() => we should override ExAdmin.Register.run_query()
    #   * To do that we redefine run_query() inside the register_resource macro
    #   * But the implementation is in an external function run_query_impl() so that everything inside the macro will be expanded during runtime (copy-pasting and modifying the contents of the original function)
    sidebar "", only: :index do
      panel "" do
        markup_contents do
          script type: "text/javascript" do
            """
            $(document).ready(function() {
              var q_project_name_html =
                `<div class="form-group">
                  <label class="label" for="q_project_name">Project Name</label>
                  <input id="q_project_name" name="project_name" class="form-control" type="text">
                </div>`
              $("#q_project_id").parent().after(q_project_name_html);

              var urlParams = new URLSearchParams(window.location.search);
              $("#q_project_name").val(urlParams.get('project_name'));
            });
            """
          end
        end
      end
    end

    def run_query(repo, defn, :index, id) do
      run_query_impl(repo, defn, :index, id)
    end
  end

  def run_query_impl(repo, defn, :index, id) do
    query = %Sanbase.ExAdmin.Model.Ico{}
    |> Map.get(:resource_model)
    |> ExAdmin.Query.run_query(repo, defn, :index, id, @query)

    List.keyfind(id, :project_name, 0)
    |> case do
      {:project_name, project_name} when is_binary(project_name) ->
        query
        |> join(:inner, [i], p in assoc(i, :project))
        |> where([i, p], like(fragment("lower(?)", p.name), ^"%#{String.replace(String.downcase(project_name), "%", "\\%")}%"))
      _ -> query
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource = resource
    |> set_cap_currency_default()
    |> set_start_date_default()
    |> set_end_date_default()
    |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(%Ico{project_id: nil}=ico, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> ico
      project_id -> Map.put(ico, :project_id, project_id)
    end
  end

  defp set_project_default(%Ico{}=ico), do: ico

  defp set_cap_currency_default(%Ico{cap_currency_id: nil}=ico) do
    currency = Currency.get("ETH")

    case currency do
      %Currency{id: id} -> Map.put(ico, :cap_currency_id, id)
      _ -> ico
    end
  end

  defp set_cap_currency_default(%Ico{}=ico), do: ico

  defp set_start_date_default(%Ico{start_date: nil}=ico) do
    Map.put(ico, :start_date, Ecto.Date.utc())
  end

  defp set_start_date_default(%Ico{}=ico), do: ico

  defp set_end_date_default(%Ico{end_date: nil}=ico) do
    Map.put(ico, :end_date, Ecto.Date.utc())
  end

  defp set_end_date_default(%Ico{}=ico), do: ico
end
