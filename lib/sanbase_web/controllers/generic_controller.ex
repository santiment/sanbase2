defmodule SanbaseWeb.GenericController do
  use SanbaseWeb, :controller

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias SanbaseWeb.Router.Helpers, as: Routes
  alias Sanbase.Repo

  @resource_module_map %{
    "users" => %{
      module: User,
      index_fields: [:id, :name, :email, :username],
      edit_fields: [:stripe_customer_id, :email],
      show_fields: :all,
      actions: [:show, :edit, :delete]
    }
  }

  def index(conn, %{"resource" => resource}) do
    render(conn, "index.html", table: resource_to_table_params(resource))
  end

  def index(conn, _) do
    render(conn, "error.html")
  end

  def search(conn, %{"resource" => resource, "search" => %{"generic_search" => search_text}}) do
    module = module_from_resource(resource)

    rows =
      case Integer.parse(search_text) do
        {id, ""} -> search_by_id(module, id)
        _ -> search_by_text(module, String.downcase(search_text))
      end

    render(conn, "index.html", table: resource_to_table_params(resource, rows))
  end

  def show(conn, %{"resource" => resource, "id" => id}) do
    module = module_from_resource(resource)
    data = Repo.get(module, id)

    render(conn, "show.html",
      resource: resource,
      data: data,
      string_fields: string_fields(module)
    )
  end

  # private

  def module_from_resource(resource), do: @resource_module_map[resource][:module]

  def resource_to_table_params(resource, rows \\ nil) do
    name = String.capitalize(resource)
    module = @resource_module_map[resource][:module]

    index_fields =
      case @resource_module_map[resource][:index_fields] do
        nil -> fields(module)
        :all -> fields(module)
        fields when is_list(fields) -> fields
      end

    %{
      resource: resource,
      resource_name: name,
      rows: rows || all(module),
      fields: index_fields,
      funcs: %{},
      actions: @resource_module_map[resource][:actions]
    }
  end

  def all(module) do
    from(
      m in module,
      order_by: [desc: m.id],
      limit: 10
    )
    |> Repo.all()
  end

  defp search_by_text(module, text) do
    module.by_search_text(text)
  end

  defp search_by_id(module, id) do
    case Repo.get(module, id) do
      nil -> []
      result -> [result]
    end
  end

  def fields(module) do
    module.__schema__(:fields)
  end

  defp string_fields(module) do
    fields(module)
  end
end
