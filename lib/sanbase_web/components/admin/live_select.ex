defmodule SanbaseWeb.LiveSelect do
  use SanbaseWeb, :live_view

  use PhoenixHTMLHelpers
  import SanbaseWeb.CoreComponents
  import Ecto.Query

  def render(assigns) do
    field = assigns.session["field"]
    parent = assigns.session["parent_resource"]
    input_value = assigns.query || assigns.session["initial_value"]

    assigns =
      assign(assigns,
        input_name: parent <> "[" <> to_string(field) <> "_id]",
        input_id: parent <> "_" <> to_string(field),
        input_value: input_value,
        datalist_id: "matches_" <> to_string(field),
        field_label: humanize(field),
        selected_label: selected_match_label(input_value, assigns.matches)
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
        class="input input-sm w-full"
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
      <div :if={@selected_label} class="mt-1 text-xs text-base-content/70 break-all">
        {@selected_label}
      </div>
      <datalist id={@datalist_id}>
        <option :for={{id, match} <- @matches} value={id}>{match}</option>
      </datalist>
    </div>
    """
  end

  defp selected_match_label(nil, _matches), do: nil
  defp selected_match_label("", _matches), do: nil

  defp selected_match_label(value, matches) do
    case Integer.parse(to_string(value)) do
      {id, ""} ->
        case Enum.find(matches, fn {match_id, _} -> match_id == id end) do
          {_, formatted} -> formatted
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def mount(_params, session, socket) do
    session =
      Map.take(session, [
        "resource",
        "search_fields",
        "field",
        "parent_resource",
        "initial_value",
        "no_label"
      ])

    initial_matches =
      case Integer.parse(to_string(session["initial_value"] || "")) do
        {id, ""} -> search_matches_by_id(id, session)
        _ -> []
      end

    {:ok,
     assign(socket,
       query: nil,
       result: nil,
       loading: false,
       matches: initial_matches,
       session: session
     ), layout: false}
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) < 2 do
    session = socket.assigns[:session]

    matches =
      case Integer.parse(query) do
        {id, ""} -> search_matches_by_id(id, session)
        _ -> []
      end

    {:noreply, assign(socket, query: query, matches: matches)}
  end

  def handle_event("suggest", %{"value" => query}, socket)
      when byte_size(query) >= 2 and byte_size(query) <= 100 do
    session = socket.assigns[:session]

    matches =
      case Integer.parse(query) do
        {id, ""} -> search_matches_by_id(id, session)
        _ -> search_matches(query, session)
      end

    {:noreply, assign(socket, query: query, matches: matches)}
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
