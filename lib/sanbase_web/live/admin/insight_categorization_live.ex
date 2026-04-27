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
      <h1 class="text-3xl font-bold mb-6">Insight Categorization</h1>

      <div class="mb-6 flex items-center gap-4">
        <div role="tablist" class="tabs tabs-boxed mr-2">
          <button
            role="tab"
            phx-click="toggle_search_mode"
            phx-value-mode="keyword"
            class={["tab", @search_mode == "keyword" && "tab-active"]}
          >
            Keyword
          </button>
          <button
            role="tab"
            phx-click="toggle_search_mode"
            phx-value-mode="semantic"
            class={["tab", @search_mode == "semantic" && "tab-active"]}
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
            class="input input-md w-full"
          />
        </form>

        <form :if={@search_mode == "keyword"} phx-change="sort" id="sort-by-form">
          <select name="sort_by" class="select select-md">
            <option value="published_at" selected={@sort_by == "published_at"}>Published Date</option>
            <option value="title" selected={@sort_by == "title"}>Title</option>
          </select>
        </form>

        <form :if={@search_mode == "keyword"} phx-change="sort" id="sort-order-form">
          <select name="sort_order" class="select select-md">
            <option value="desc" selected={@sort_order == "desc"}>Descending</option>
            <option value="asc" selected={@sort_order == "asc"}>Ascending</option>
          </select>
        </form>
      </div>

      <div class="mb-4 flex items-center justify-between text-sm text-base-content/70">
        <div>
          <span class="font-medium">Total:</span> {@total_count}
          <span :if={@search_mode == "keyword"} class="mx-2">•</span>
          <span :if={@search_mode == "keyword"}>Page {@page} of {@total_pages}</span>
          <span :if={@search_mode == "semantic"} class="mx-2">•</span>
          <span :if={@search_mode == "semantic"} class="text-primary font-medium">
            Semantic Search
          </span>
        </div>
        <button phx-click="load_stats" phx-disable-with="Loading..." class="btn btn-sm btn-secondary">
          Load Stats
        </button>
      </div>

      <div
        :if={@show_stats && @stats}
        class="mb-6 p-4 bg-base-200 rounded-box border border-base-300"
      >
        <h3 class="text-lg font-semibold mb-3">Categorization Stats</h3>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          <div class="card bg-base-100 border border-base-300 p-3">
            <div class="text-2xl font-bold text-secondary">{@stats.total_categorized}</div>
            <div class="text-sm text-base-content/70">Total Categorized</div>
          </div>
          <div
            :for={cat <- @stats.by_category}
            class="card bg-base-100 border border-base-300 p-3"
          >
            <div class="text-2xl font-bold text-primary">{cat.count}</div>
            <div class="text-sm text-base-content/70">{cat.category_name}</div>
          </div>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Title</th>
              <th>Author</th>
              <th>Published</th>
              <th>Categories</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={post <- @posts}
              id={"post-#{post.id}"}
              class="cursor-pointer"
              phx-click="select_post"
              phx-value-post_id={post.id}
            >
              <td>
                <.link
                  navigate={~p"/admin/generic/#{post.id}?resource=posts"}
                  class="text-sm font-medium link link-primary"
                  phx-click="noop"
                >
                  {String.slice(post.title || "", 0..50)}{if String.length(post.title || "") > 50,
                    do: "..."}
                </.link>
              </td>
              <td class="text-sm">{post.user.email}</td>
              <td class="text-sm text-base-content/60">
                {if post.published_at, do: Calendar.strftime(post.published_at, "%Y-%m-%d")}
              </td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={mapping <- post.category_mappings}
                    class={[
                      "badge badge-sm",
                      if(mapping.source == "human", do: "badge-success", else: "badge-info")
                    ]}
                  >
                    {mapping.category_name}
                    {if mapping.source == "human", do: " (H)", else: " (AI)"}
                  </span>
                </div>
              </td>
              <td>
                <button
                  phx-click="auto_categorize"
                  phx-value-post_id={post.id}
                  class="link link-primary text-sm"
                >
                  Auto-categorize
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@search_mode == "keyword"} class="mt-4 flex items-center justify-between">
        <button phx-click="prev_page" disabled={@page == 1} class="btn btn-sm btn-soft">
          Previous
        </button>
        <span class="text-sm text-base-content/70">
          Page {@page} of {@total_pages}
        </span>
        <button
          phx-click="next_page"
          disabled={@page == @total_pages}
          class="btn btn-sm btn-soft"
        >
          Next
        </button>
      </div>
    </div>

    <div :if={@selected_post} class="modal modal-open">
      <div class="modal-box max-w-3xl" phx-click="noop">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-medium">{@selected_post.title}</h3>
          <button
            type="button"
            phx-click="close_modal"
            class="btn btn-sm btn-ghost btn-circle"
            aria-label="Close modal"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="mb-4">
          <p class="text-sm text-base-content/70 mb-2">
            <strong>Author:</strong> {@selected_post.user.email}
          </p>
          <p class="text-sm text-base-content/70 mb-4">
            <strong>Published:</strong>{" "}
            {if @selected_post.published_at,
              do: Calendar.strftime(@selected_post.published_at, "%Y-%m-%d %H:%M"),
              else: "N/A"}
          </p>
        </div>

        <div class="mb-6">
          <h4 class="text-sm font-medium mb-2">Content:</h4>
          <div class="prose max-w-none text-sm whitespace-pre-wrap">
            {@selected_post.text}
          </div>
        </div>

        <form phx-submit="save_categories" class="mb-4" phx-click="noop">
          <input type="hidden" name="post_id" value={@selected_post.id} />
          <h4 class="text-sm font-medium mb-3">Categories:</h4>
          <div class="space-y-2">
            <label
              :for={category <- @all_categories}
              class="label cursor-pointer justify-start gap-2"
              phx-click="noop"
            >
              <input
                type="checkbox"
                name="category_ids[]"
                value={category.id}
                checked={Enum.any?(@post_categories, fn m -> m.category_id == category.id end)}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="label-text">{category.name}</span>
            </label>
          </div>
          <button type="submit" class="btn btn-sm btn-primary mt-4">
            Save Categories
          </button>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>
    """
  end
end
