defmodule SanbaseWeb.LiveSelect do
  use SanbaseWeb, :live_view

  use PhoenixHTMLHelpers
  import SanbaseWeb.CoreComponents
  import Ecto.Query

  def render(assigns) do
    field = assigns.session["field"]
    parent = assigns.session["parent_resource"]

    assigns =
      assign(assigns,
        input_name: parent <> "[" <> to_string(field) <> "_id]",
        input_id: parent <> "_" <> to_string(field),
        input_value: assigns.query || assigns.session["initial_value"],
        datalist_id: "matches_" <> to_string(field),
        field_label: humanize(field)
      )

    ~H"""
    <div class="w-full">
      <input
        :if={@session["no_label"]}
        type="text"
        name={@input_name}
        id={@input_id}
        value={@input_value}
        list={@datalist_id}
        phx-keyup="suggest"
        phx-debounce="200"
        placeholder="Search..."
        class="block w-full rounded-md border border-zinc-300 px-2 py-1 text-zinc-900 focus:border-zinc-400 focus:ring-0 text-sm leading-5"
      />
      <.input
        :if={!@session["no_label"]}
        type="text"
        label={@field_label}
        name={@input_name}
        value={@input_value}
        list={@datalist_id}
        phx-keyup="suggest"
        phx-debounce="200"
        placeholder="Search..."
      />
      <datalist id={@datalist_id}>
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
           "initial_value",
           "no_label"
         ])
     ), layout: false}
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) < 2 do
    session = socket.assigns[:session]

    Integer.parse(query)
    |> case do
      {id, ""} -> {:noreply, assign(socket, matches: search_matches_by_id(id, session))}
      _ -> {:noreply, assign(socket, matches: [])}
    end
  end

  def handle_event("suggest", %{"value" => query}, socket)
      when byte_size(query) >= 2 and byte_size(query) <= 100 do
    session = socket.assigns[:session]

    Integer.parse(query)
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
    Enum.reduce(search_fields, base_query, fn field, acc ->
      or_where(acc, [p], field(p, ^field) == ^value)
    end)
    |> select_merge([p], map(p, [:id]))
    |> select_merge([p], map(p, ^search_fields))
    |> order_by([p], desc: p.id)
  end

  defp build_partial_match_query(search_fields, base_query, value) do
    Enum.reduce(search_fields, base_query, fn field, acc ->
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
      formatted = Enum.map(result, fn {key, value} -> "#{key}: #{value}" end) |> Enum.join(", ")
      {result.id, formatted}
    end)
  end
end
