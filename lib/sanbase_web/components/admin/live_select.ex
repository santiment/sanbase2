defmodule SanbaseWeb.LiveSelect do
  @moduledoc false
  use SanbaseWeb, :live_view
  use PhoenixHTMLHelpers

  import Ecto.Query
  import SanbaseWeb.CoreComponents

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.input
        type="text"
        label={humanize(@session["field"])}
        name={@session["parent_resource"] <> "[" <> to_string(@session["field"]) <> "_id" <> "]"}
        value={@query || @session["initial_value"]}
        list={"matches_" <> to_string(@session["field"])}
        phx-keyup="suggest"
        phx-debounce="200"
        placeholder="Search..."
      />
      <datalist id={"matches_" <> to_string(@session["field"])}>
        <%= for {id, match} <- @matches do %>
          <option value={id}>{match}</option>
        <% end %>
      </datalist>
    </div>
    """
  end

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       query: nil,
       result: nil,
       loading: false,
       matches: [],
       session:
         Map.take(session, [
           "resource",
           "search_fields",
           "field",
           "parent_resource",
           "initial_value"
         ])
     ), layout: false}
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) < 2 do
    session = socket.assigns[:session]

    query
    |> Integer.parse()
    |> case do
      {id, ""} -> {:noreply, assign(socket, matches: search_matches_by_id(id, session))}
      _ -> {:noreply, assign(socket, matches: [])}
    end
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) >= 2 and byte_size(query) <= 100 do
    session = socket.assigns[:session]

    query
    |> Integer.parse()
    |> case do
      {id, ""} -> {:noreply, assign(socket, matches: search_matches_by_id(id, session))}
      _ -> {:noreply, assign(socket, matches: search_matches(query, session))}
    end
  end

  def search_matches_by_id(id, session) do
    resource = session["resource"]
    search_fields = session["search_fields"]
    resource_module_map = SanbaseWeb.GenericAdmin.resource_module_map()
    module = resource_module_map[resource][:module]

    full_match_query =
      from(m in module, where: m.id == ^id, select_merge: %{})
      |> select_merge([p], map(p, [:id]))
      |> select_merge([p], map(p, ^search_fields))

    full_matches = Sanbase.Repo.all(full_match_query)

    format_results(full_matches, [])
  end

  def search_matches(query, session) do
    resource = session["resource"]
    search_fields = session["search_fields"]
    resource_module_map = SanbaseWeb.GenericAdmin.resource_module_map()
    module = resource_module_map[resource][:module]
    value = "%" <> query <> "%"

    base_query = from(m in module, select_merge: %{})

    full_match_query = build_full_match_query(search_fields, base_query, query)
    partial_match_query = build_partial_match_query(search_fields, base_query, value)

    full_matches = Sanbase.Repo.all(full_match_query)
    partial_matches = Sanbase.Repo.all(partial_match_query)

    format_results(full_matches, partial_matches)
  end

  defp build_full_match_query(search_fields, base_query, value) do
    search_fields
    |> Enum.reduce(base_query, fn field, acc ->
      or_where(acc, [p], field(p, ^field) == ^value)
    end)
    |> select_merge([p], map(p, [:id]))
    |> select_merge([p], map(p, ^search_fields))
    |> order_by([p], desc: p.id)
  end

  defp build_partial_match_query(search_fields, base_query, value) do
    search_fields
    |> Enum.reduce(base_query, fn field, acc ->
      or_where(acc, [p], ilike(field(p, ^field), ^value))
    end)
    |> select_merge([p], map(p, [:id]))
    |> select_merge([p], map(p, ^search_fields))
    |> order_by([p], desc: p.id)
  end

  defp format_results(full_matches, partial_matches) do
    (full_matches ++ partial_matches)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(10)
    |> Enum.map(fn result ->
      formatted = Enum.map_join(result, ", ", fn {key, value} -> "#{key}: #{value}" end)
      {result.id, formatted}
    end)
  end
end
