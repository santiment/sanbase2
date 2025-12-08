defmodule SanbaseWeb.Admin.InsightCategorizationLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Insight.{Post, Category, PostCategory, Categorizer}

  @default_page_size 50

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Insight Categorization")
      |> assign(:search_term, "")
      |> assign(:search_mode, "keyword")
      |> assign(:sort_by, "published_at")
      |> assign(:sort_order, "desc")
      |> assign(:selected_post, nil)
      |> assign(:all_categories, Category.all())
      |> assign(:stats, nil)
      |> assign(:show_stats, false)
      |> assign_pagination(%{})

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    search_mode = socket.assigns[:search_mode] || "keyword"
    search_term = Map.get(params, "search_term", socket.assigns[:search_term] || "")

    socket =
      socket
      |> assign(:search_term, search_term)
      |> assign(:sort_by, Map.get(params, "sort_by", socket.assigns[:sort_by] || "published_at"))
      |> assign(:sort_order, Map.get(params, "sort_order", socket.assigns[:sort_order] || "desc"))

    socket =
      if search_mode == "semantic" and search_term != "" do
        assign_semantic_results(socket, search_term)
      else
        assign_pagination(socket, params)
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"search_term" => search_term}, socket) do
    socket =
      socket
      |> assign(:search_term, search_term)
      |> assign(:page, 1)

    socket =
      if socket.assigns.search_mode == "semantic" do
        assign_semantic_results(socket, search_term)
      else
        assign_pagination(socket, %{})
      end

    {:noreply, socket}
  end

  def handle_event("toggle_search_mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:search_mode, mode)
     |> assign(:search_term, "")
     |> assign(:page, 1)
     |> assign_pagination(%{})}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign_pagination(%{})}
  end

  def handle_event("sort", %{"sort_order" => sort_order}, socket) do
    {:noreply,
     socket
     |> assign(:sort_order, sort_order)
     |> assign_pagination(%{})}
  end

  def handle_event("prev_page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply,
       push_patch(socket,
         to: ~p"/admin/insight_categorization?#{[page: socket.assigns.page - 1]}"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("next_page", _, socket) do
    if socket.assigns.page < socket.assigns.total_pages do
      {:noreply,
       push_patch(socket,
         to: ~p"/admin/insight_categorization?#{[page: socket.assigns.page + 1]}"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_post", %{"post_id" => post_id}, socket) do
    post_id = String.to_integer(post_id)

    post =
      Post.by_id(post_id, preload?: true, preload: [:user, :categories])
      |> case do
        {:ok, post} -> post
        _ -> nil
      end

    categories = PostCategory.get_post_categories(post_id)

    {:noreply,
     socket
     |> assign(:selected_post, post)
     |> assign(:post_categories, categories)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :selected_post, nil)}
  end

  def handle_event("noop", _, socket) do
    {:noreply, socket}
  end

  def handle_event("save_categories", %{"post_id" => post_id} = params, socket) do
    post_id = String.to_integer(post_id)

    category_ids =
      params
      |> Map.get("category_ids", [])
      |> Enum.map(&String.to_integer/1)
      |> Enum.uniq()

    {:ok, _} = PostCategory.override_with_human_categories(post_id, category_ids)

    post =
      Post.by_id(post_id, preload?: true, preload: [:user, :categories])
      |> case do
        {:ok, post} -> post
        _ -> socket.assigns.selected_post
      end

    categories = PostCategory.get_post_categories(post_id)

    {:noreply,
     socket
     |> put_flash(:info, "Categories saved successfully")
     |> assign(:selected_post, post)
     |> assign(:post_categories, categories)
     |> assign_pagination(%{})}
  end

  def handle_event("load_stats", _, socket) do
    stats = PostCategory.get_categorization_stats()

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:show_stats, true)}
  end

  def handle_event("auto_categorize", %{"post_id" => post_id}, socket) do
    post_id = String.to_integer(post_id)

    case Categorizer.categorize_insight(post_id, save: true, force: false) do
      {:ok, category_names} ->
        post =
          Post.by_id(post_id, preload?: true, preload: [:user, :categories])
          |> case do
            {:ok, post} -> post
            _ -> socket.assigns.selected_post
          end

        categories = PostCategory.get_post_categories(post_id)

        {:noreply,
         socket
         |> put_flash(:info, "Auto-categorized: #{Enum.join(category_names, ", ")}")
         |> assign(:selected_post, post)
         |> assign(:post_categories, categories)
         |> assign_pagination(%{})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to categorize: #{inspect(reason)}")}
    end
  end

  defp assign_pagination(socket, params) do
    page = parse_int(Map.get(params, "page"), socket.assigns[:page] || 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size)
    search_term = socket.assigns[:search_term] || ""
    sort_by = socket.assigns[:sort_by] || "published_at"
    sort_order = socket.assigns[:sort_order] || "desc"

    {posts, total_count, total_pages, page} =
      Post.admin_keyword_search(search_term,
        page: page,
        page_size: page_size,
        sort_by: sort_by,
        sort_order: sort_order
      )

    post_ids = Enum.map(posts, & &1.id)
    categories_by_post_id = PostCategory.get_categories_for_posts(post_ids)

    posts =
      Enum.map(posts, fn post ->
        categories = Map.get(categories_by_post_id, post.id, [])
        Map.put(post, :category_mappings, categories)
      end)

    socket
    |> assign(:posts, posts)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:search_term, search_term)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
  end

  defp assign_semantic_results(socket, search_term) do
    {posts, total_count} = Post.admin_semantic_search(search_term, 50)

    post_ids = Enum.map(posts, & &1.id)
    categories_by_post_id = PostCategory.get_categories_for_posts(post_ids)

    posts =
      Enum.map(posts, fn post ->
        categories = Map.get(categories_by_post_id, post.id, [])
        Map.put(post, :category_mappings, categories)
      end)

    socket
    |> assign(:posts, posts)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, 1)
    |> assign(:page, 1)
    |> assign(:page_size, 50)
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_binary(value), do: String.to_integer(value)
  defp parse_int(value, _default), do: value

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">Insight Categorization</h1>

      <div class="mb-6 flex items-center gap-4">
        <div class="flex gap-2 mr-2">
          <button
            phx-click="toggle_search_mode"
            phx-value-mode="keyword"
            class={[
              "px-3 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@search_mode == "keyword",
                do: "bg-blue-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            Keyword
          </button>
          <button
            phx-click="toggle_search_mode"
            phx-value-mode="semantic"
            class={[
              "px-3 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@search_mode == "semantic",
                do: "bg-blue-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            Semantic
          </button>
        </div>

        <form phx-submit="search" class="flex-1">
          <input
            type="text"
            name="search_term"
            value={@search_term}
            placeholder={
              if(@search_mode == "semantic",
                do: "Search insights semantically...",
                else: "Search insights by title or content..."
              )
            }
            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </form>

        <form :if={@search_mode == "keyword"} phx-change="sort" id="sort-by-form">
          <select name="sort_by" class="px-4 py-2 border border-gray-300 rounded-lg">
            <option value="published_at" selected={@sort_by == "published_at"}>Published Date</option>
            <option value="title" selected={@sort_by == "title"}>Title</option>
          </select>
        </form>

        <form :if={@search_mode == "keyword"} phx-change="sort" id="sort-order-form">
          <select name="sort_order" class="px-4 py-2 border border-gray-300 rounded-lg">
            <option value="desc" selected={@sort_order == "desc"}>Descending</option>
            <option value="asc" selected={@sort_order == "asc"}>Ascending</option>
          </select>
        </form>
      </div>

      <div class="mb-4 flex items-center justify-between text-sm text-gray-600">
        <div>
          <span class="font-medium">Total:</span> {@total_count}
          <span :if={@search_mode == "keyword"} class="mx-2">•</span>
          <span :if={@search_mode == "keyword"}>Page {@page} of {@total_pages}</span>
          <span :if={@search_mode == "semantic"} class="mx-2">•</span>
          <span :if={@search_mode == "semantic"} class="text-blue-600 font-medium">
            Semantic Search
          </span>
        </div>
        <button
          phx-click="load_stats"
          phx-disable-with="Loading..."
          class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 text-sm"
        >
          Load Stats
        </button>
      </div>

      <div :if={@show_stats && @stats} class="mb-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Categorization Stats</h3>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          <div class="bg-white p-3 rounded-lg shadow-sm border border-gray-100">
            <div class="text-2xl font-bold text-purple-600">{@stats.total_categorized}</div>
            <div class="text-sm text-gray-600">Total Categorized</div>
          </div>
          <div
            :for={cat <- @stats.by_category}
            class="bg-white p-3 rounded-lg shadow-sm border border-gray-100"
          >
            <div class="text-2xl font-bold text-blue-600">{cat.count}</div>
            <div class="text-sm text-gray-600">{cat.category_name}</div>
          </div>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Title
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Author
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Published
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Categories
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr
              :for={post <- @posts}
              id={"post-#{post.id}"}
              class="hover:bg-gray-50 cursor-pointer"
              phx-click="select_post"
              phx-value-post_id={post.id}
            >
              <td class="px-6 py-4 whitespace-nowrap">
                <.link
                  navigate={~p"/admin/generic/#{post.id}?resource=posts"}
                  class="text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline"
                  phx-click="noop"
                >
                  {String.slice(post.title || "", 0..50)}
                  {if String.length(post.title || "") > 50, do: "..."}
                </.link>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-900">{post.user.email}</div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-500">
                  {if post.published_at, do: Calendar.strftime(post.published_at, "%Y-%m-%d")}
                </div>
              </td>
              <td class="px-6 py-4">
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={mapping <- post.category_mappings}
                    class={[
                      "px-2 py-1 text-xs rounded",
                      if(mapping.source == "human",
                        do: "bg-green-100 text-green-800",
                        else: "bg-blue-100 text-blue-800"
                      )
                    ]}
                  >
                    {mapping.category_name}
                    {if mapping.source == "human", do: " (H)", else: " (AI)"}
                  </span>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm">
                <button
                  phx-click="auto_categorize"
                  phx-value-post_id={post.id}
                  class="text-blue-600 hover:text-blue-900"
                >
                  Auto-categorize
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@search_mode == "keyword"} class="mt-4 flex items-center justify-between">
        <button
          phx-click="prev_page"
          disabled={@page == 1}
          class={[
            "px-4 py-2 rounded border",
            if(@page == 1,
              do: "text-gray-400 border-gray-200 cursor-not-allowed",
              else: "text-gray-700 border-gray-300 hover:bg-gray-50"
            )
          ]}
        >
          Previous
        </button>
        <span class="text-sm text-gray-600">
          Page {@page} of {@total_pages}
        </span>
        <button
          phx-click="next_page"
          disabled={@page == @total_pages}
          class={[
            "px-4 py-2 rounded border",
            if(@page == @total_pages,
              do: "text-gray-400 border-gray-200 cursor-not-allowed",
              else: "text-gray-700 border-gray-300 hover:bg-gray-50"
            )
          ]}
        >
          Next
        </button>
      </div>
    </div>

    <div :if={@selected_post}>
      <div
        class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50"
        id="modal-backdrop"
        phx-click="close_modal"
      >
        <div
          class="relative top-20 mx-auto p-5 border w-11/12 max-w-3xl shadow-lg rounded-md bg-white"
          phx-click="noop"
        >
          <div class="mt-3">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-lg font-medium text-gray-900">{@selected_post.title}</h3>
              <button
                type="button"
                phx-click="close_modal"
                class="text-gray-400 hover:text-gray-600"
                aria-label="Close modal"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            <div class="mb-4">
              <p class="text-sm text-gray-600 mb-2">
                <strong>Author:</strong> {@selected_post.user.email}
              </p>
              <p class="text-sm text-gray-600 mb-4">
                <strong>Published:</strong>{" "}
                {if @selected_post.published_at,
                  do: Calendar.strftime(@selected_post.published_at, "%Y-%m-%d %H:%M"),
                  else: "N/A"}
              </p>
            </div>

            <div class="mb-6">
              <h4 class="text-sm font-medium text-gray-700 mb-2">Content:</h4>
              <div class="prose max-w-none text-sm text-gray-700 whitespace-pre-wrap">
                {@selected_post.text}
              </div>
            </div>

            <form phx-submit="save_categories" class="mb-4" phx-click="noop">
              <input type="hidden" name="post_id" value={@selected_post.id} />
              <h4 class="text-sm font-medium text-gray-700 mb-3">Categories:</h4>
              <div class="space-y-2">
                <label
                  :for={category <- @all_categories}
                  class="flex items-center space-x-2 cursor-pointer"
                  phx-click="noop"
                >
                  <input
                    type="checkbox"
                    name="category_ids[]"
                    value={category.id}
                    checked={Enum.any?(@post_categories, fn m -> m.category_id == category.id end)}
                    class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                  <span class="text-sm text-gray-700">{category.name}</span>
                </label>
              </div>
              <button
                type="submit"
                class="mt-4 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Save Categories
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
