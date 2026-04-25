defmodule SanbaseWeb.Admin.AiDescriptionLive do
  use SanbaseWeb, :live_view

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.Chart.Configuration
  alias Sanbase.UserList
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.AI.DescriptionJob

  @default_page_size 20
  @allowed_entity_types [:charts, :screeners, :watchlists, :insights]

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    if connected?(socket), do: DescriptionJob.subscribe()

    job_state = DescriptionJob.get_state()

    socket =
      socket
      |> assign(:page_title, "AI Description Generator")
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:selected_user, nil)
      |> assign(:entity_type, :charts)
      |> assign(:custom_prompt, "")
      |> assign(:custom_prompt_error, nil)
      |> assign(:global_refinement_prompt, DescriptionJob.default_refinement_prompt())
      |> assign(:form, to_form(%{"custom_prompt" => ""}, as: :custom_prompt))
      |> assign(:loading_ids, MapSet.new())
      |> assign(:selected_entity, nil)
      |> assign(:page, 1)
      |> assign(:page_size, @default_page_size)
      |> assign(:total_count, 0)
      |> assign(:total_pages, 1)
      |> assign(:tab_counts, %{charts: 0, screeners: 0, watchlists: 0, insights: 0})
      |> assign(:entities, [])
      |> assign(:bulk_job, if(job_state.status == :idle, do: nil, else: job_state))
      |> assign(:show_override_confirm, false)
      |> assign(:pending_entities_reload, false)
      |> assign(:reload_timer_ref, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Handle params
  # ---------------------------------------------------------------------------

  def handle_params(params, _uri, socket) do
    page = parse_int(Map.get(params, "page"), 1)
    user_id = parse_int_or_nil(Map.get(params, "user_id"))

    socket =
      socket
      |> assign(:page, page)
      |> maybe_load_user_from_param(user_id)
      |> maybe_load_entities()

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — search
  # ---------------------------------------------------------------------------

  def handle_event("search_user", params, socket) do
    query = String.trim(Map.get(params, "query", Map.get(params, "value", "")))
    results = if String.length(query) >= 1, do: search_users(query), else: []

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:search_results, results)

    {:noreply, socket}
  end

  def handle_event("select_user", %{"user_id" => uid_str}, socket) do
    case Integer.parse(uid_str) do
      {user_id, ""} ->
        socket = assign(socket, :search_results, [])

        {:noreply,
         push_patch(socket, to: ~p"/admin/ai_descriptions?#{[user_id: user_id, page: 1]}")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_user", _, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:selected_entity, nil)

    {:noreply, push_patch(socket, to: ~p"/admin/ai_descriptions")}
  end

  # ---------------------------------------------------------------------------
  # Events — tabs & prompt
  # ---------------------------------------------------------------------------

  def handle_event("select_tab", %{"type" => type}, socket) do
    case validate_entity_type(type) do
      {:ok, entity_type} ->
        socket =
          socket
          |> assign(:entity_type, entity_type)
          |> assign(:page, 1)
          |> assign(:selected_entity, nil)
          |> maybe_load_entities()

        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("select_tab", _, socket), do: {:noreply, socket}

  def handle_event(
        "update_custom_prompt",
        %{"custom_prompt" => %{"custom_prompt" => value}},
        socket
      ) do
    socket =
      socket
      |> assign(:custom_prompt, value)
      |> assign(:custom_prompt_error, nil)
      |> assign_custom_prompt_form(value)

    {:noreply, socket}
  end

  def handle_event("update_custom_prompt", %{"custom_prompt" => value}, socket) do
    socket =
      socket
      |> assign(:custom_prompt, value)
      |> assign(:custom_prompt_error, nil)
      |> assign_custom_prompt_form(value)

    {:noreply, socket}
  end

  def handle_event("save_custom_prompt", params, socket) do
    prompt = extract_custom_prompt_param(params)

    case socket.assigns.selected_user do
      nil ->
        {:noreply, put_flash(socket, :error, "No user selected")}

      user ->
        case UserSettings.set_ai_refinement_prompt(user.id, prompt) do
          {:ok, _} ->
            socket =
              socket
              |> assign(:custom_prompt, prompt)
              |> assign_custom_prompt_form(prompt)
              |> assign(:custom_prompt_error, nil)
              |> put_flash(:info, "Custom refinement prompt saved")

            {:noreply, socket}

          {:error, reason} ->
            error = inspect(reason)

            socket =
              socket
              |> assign(:custom_prompt, prompt)
              |> assign_custom_prompt_form(prompt)
              |> assign(:custom_prompt_error, error)
              |> put_flash(:error, "Failed to save custom refinement prompt")

            {:noreply, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Events — single generation
  # ---------------------------------------------------------------------------

  def handle_event("generate", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        entity = Enum.find(socket.assigns.entities, fn e -> e.id == id end)

        if entity do
          loading_ids = MapSet.put(socket.assigns.loading_ids, id)
          lv_pid = self()
          entity_type = socket.assigns.entity_type
          custom_prompt = effective_custom_prompt(socket.assigns.custom_prompt)

          Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
            try do
              result = DescriptionJob.run_generation(entity, entity_type, custom_prompt)
              send(lv_pid, {:generation_done, entity_type, id, result})
            rescue
              e ->
                send(lv_pid, {:generation_done, entity_type, id, {:error, Exception.message(e)}})
            end
          end)

          {:noreply, assign(socket, :loading_ids, loading_ids)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("generate_selected", _, socket) do
    entity = socket.assigns.selected_entity

    if entity do
      loading_ids = MapSet.put(socket.assigns.loading_ids, entity.id)
      lv_pid = self()
      entity_type = socket.assigns.entity_type
      custom_prompt = effective_custom_prompt(socket.assigns.custom_prompt)

      Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
        try do
          result = DescriptionJob.run_generation(entity, entity_type, custom_prompt)
          send(lv_pid, {:generation_done, entity_type, entity.id, result})
        rescue
          e ->
            send(
              lv_pid,
              {:generation_done, entity_type, entity.id, {:error, Exception.message(e)}}
            )
        end
      end)

      {:noreply, assign(socket, :loading_ids, loading_ids)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — bulk generation
  # ---------------------------------------------------------------------------

  def handle_event("bulk_generate", _, socket) do
    user = socket.assigns.selected_user

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "Select a user first")}
    else
      pending =
        [:charts, :screeners, :watchlists, :insights]
        |> Enum.flat_map(&fetch_all_pending(&1, user.id))

      if pending == [] do
        {:noreply, put_flash(socket, :info, "All entities already have AI descriptions")}
      else
        custom_prompt = effective_custom_prompt(socket.assigns.custom_prompt)

        case DescriptionJob.start_job(user.id, :all, pending, custom_prompt) do
          :ok ->
            {:noreply, socket}

          {:error, :already_running} ->
            {:noreply, put_flash(socket, :error, "A bulk generation job is already running")}
        end
      end
    end
  end

  def handle_event("bulk_cancel", _, socket) do
    DescriptionJob.cancel()
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — override
  # ---------------------------------------------------------------------------

  def handle_event("show_override_confirm", _, socket) do
    {:noreply, assign(socket, :show_override_confirm, true)}
  end

  def handle_event("hide_override_confirm", _, socket) do
    {:noreply, assign(socket, :show_override_confirm, false)}
  end

  def handle_event("confirm_override", _, socket) do
    user = socket.assigns.selected_user
    entity_type = socket.assigns.entity_type

    if is_nil(user) do
      {:noreply,
       socket |> assign(:show_override_confirm, false) |> put_flash(:error, "No user selected")}
    else
      {count, _} = override_descriptions(entity_type, user.id)

      socket =
        socket
        |> assign(:show_override_confirm, false)
        |> put_flash(:info, "Overrode description with AI description for #{count} entities")
        |> maybe_load_entities()

      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — pagination & modal
  # ---------------------------------------------------------------------------

  def handle_event("select_entity", %{"id" => id}, socket) do
    id = String.to_integer(id)
    entity = Enum.find(socket.assigns.entities, fn e -> e.id == id end)
    {:noreply, assign(socket, :selected_entity, entity)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :selected_entity, nil)}
  end

  def handle_event("noop", _, socket) do
    {:noreply, socket}
  end

  def handle_event("prev_page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, push_patch(socket, to: page_url(socket, socket.assigns.page - 1))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("next_page", _, socket) do
    if socket.assigns.page < socket.assigns.total_pages do
      {:noreply, push_patch(socket, to: page_url(socket, socket.assigns.page + 1))}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Handle info — single generation result
  # ---------------------------------------------------------------------------

  def handle_info({:generation_done, entity_type, id, {:ok, ai_description}}, socket) do
    DescriptionJob.save_ai_description(entity_type, id, ai_description)
    loading_ids = MapSet.delete(socket.assigns.loading_ids, id)

    entities = update_entity_ai_desc(socket.assigns.entities, id, ai_description)

    selected_entity =
      if socket.assigns.selected_entity && socket.assigns.selected_entity.id == id do
        Map.put(socket.assigns.selected_entity, :ai_description, ai_description)
      else
        socket.assigns.selected_entity
      end

    socket =
      socket
      |> assign(:loading_ids, loading_ids)
      |> assign(:entities, entities)
      |> assign(:selected_entity, selected_entity)
      |> put_flash(:info, "Description generated")

    {:noreply, socket}
  end

  def handle_info({:generation_done, _entity_type, id, {:error, reason}}, socket) do
    loading_ids = MapSet.delete(socket.assigns.loading_ids, id)

    {:noreply,
     socket
     |> assign(:loading_ids, loading_ids)
     |> put_flash(:error, "Generation failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # Handle info — bulk generation progress (GenServer PubSub)
  # ---------------------------------------------------------------------------

  def handle_info({:job_update, job_state}, socket) do
    bulk_job = if job_state.status == :idle, do: nil, else: job_state

    socket = assign(socket, :bulk_job, bulk_job)

    socket =
      case job_state.status do
        :done ->
          put_flash(
            socket,
            :info,
            "Bulk generation complete — #{job_state.done} done, #{job_state.failed} failed"
          )

        :failed ->
          put_flash(socket, :error, "Bulk generation job crashed unexpectedly")

        _ ->
          socket
      end

    socket =
      if socket.assigns.selected_user &&
           socket.assigns.selected_user.id == job_state.user_id do
        socket = assign(socket, :pending_entities_reload, true)

        if socket.assigns.reload_timer_ref do
          socket
        else
          ref = Process.send_after(self(), :reload_entities, 1_000)
          assign(socket, :reload_timer_ref, ref)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:reload_entities, socket) do
    socket =
      socket
      |> assign(:pending_entities_reload, false)
      |> assign(:reload_timer_ref, nil)

    socket =
      if socket.assigns.selected_user do
        load_entities(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  # Ignore stale Task supervisor messages
  def handle_info({ref, _result}, socket) when is_reference(ref), do: {:noreply, socket}
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private — data loading
  # ---------------------------------------------------------------------------

  defp validate_entity_type(type) when is_binary(type) do
    case String.to_existing_atom(type) do
      atom when atom in @allowed_entity_types -> {:ok, atom}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp validate_entity_type(_), do: :error

  defp maybe_load_entities(socket) do
    if socket.assigns.selected_user do
      load_entities(socket)
    else
      socket
    end
  end

  defp load_entities(socket) do
    %{entity_type: entity_type, page: page, page_size: page_size, selected_user: user} =
      socket.assigns

    offset = (page - 1) * page_size
    {entities, total_count} = fetch_entities(entity_type, user.id, page_size, offset)
    total_pages = max(1, ceil(total_count / page_size))

    tab_counts = %{
      charts: count_entities(:charts, user.id),
      screeners: count_entities(:screeners, user.id),
      watchlists: count_entities(:watchlists, user.id),
      insights: count_entities(:insights, user.id)
    }

    socket
    |> assign(:entities, entities)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:tab_counts, tab_counts)
  end

  defp fetch_entities(:insights, user_id, limit, offset) do
    base =
      from(p in Post,
        where: p.is_deleted == false and p.user_id == ^user_id,
        preload: [:user],
        order_by: [desc: p.inserted_at]
      )

    count = Repo.aggregate(base, :count, :id)
    entities = Repo.all(from(q in base, limit: ^limit, offset: ^offset))
    {entities, count}
  end

  defp fetch_entities(:charts, user_id, limit, offset) do
    base =
      from(c in Configuration,
        where: c.is_deleted == false and c.user_id == ^user_id,
        preload: [:user],
        order_by: [desc: c.inserted_at]
      )

    count = Repo.aggregate(base, :count, :id)
    entities = Repo.all(from(q in base, limit: ^limit, offset: ^offset))
    {entities, count}
  end

  defp fetch_entities(:screeners, user_id, limit, offset) do
    base =
      from(ul in UserList,
        where: ul.is_deleted == false and ul.is_screener == true and ul.user_id == ^user_id,
        preload: [:user],
        order_by: [desc: ul.inserted_at]
      )

    count = Repo.aggregate(base, :count, :id)
    entities = Repo.all(from(q in base, limit: ^limit, offset: ^offset))
    {entities, count}
  end

  defp fetch_entities(:watchlists, user_id, limit, offset) do
    base =
      from(ul in UserList,
        where: ul.is_deleted == false and ul.is_screener == false and ul.user_id == ^user_id,
        preload: [:user],
        order_by: [desc: ul.inserted_at]
      )

    count = Repo.aggregate(base, :count, :id)
    entities = Repo.all(from(q in base, limit: ^limit, offset: ^offset))
    {entities, count}
  end

  # Returns {id, type} pairs only — full records are loaded in batches inside DescriptionJob.
  defp fetch_all_pending(:insights, user_id) do
    Repo.all(
      from(p in Post,
        where: p.is_deleted == false and p.user_id == ^user_id and is_nil(p.ai_description),
        order_by: [desc: p.inserted_at],
        select: p.id
      )
    )
    |> Enum.map(&{&1, :insights})
  end

  defp fetch_all_pending(:charts, user_id) do
    Repo.all(
      from(c in Configuration,
        where: c.is_deleted == false and c.user_id == ^user_id and is_nil(c.ai_description),
        order_by: [desc: c.inserted_at],
        select: c.id
      )
    )
    |> Enum.map(&{&1, :charts})
  end

  defp fetch_all_pending(:screeners, user_id) do
    Repo.all(
      from(ul in UserList,
        where:
          ul.is_deleted == false and ul.is_screener == true and ul.user_id == ^user_id and
            is_nil(ul.ai_description),
        order_by: [desc: ul.inserted_at],
        select: ul.id
      )
    )
    |> Enum.map(&{&1, :screeners})
  end

  defp fetch_all_pending(:watchlists, user_id) do
    Repo.all(
      from(ul in UserList,
        where:
          ul.is_deleted == false and ul.is_screener == false and ul.user_id == ^user_id and
            is_nil(ul.ai_description),
        order_by: [desc: ul.inserted_at],
        select: ul.id
      )
    )
    |> Enum.map(&{&1, :watchlists})
  end

  defp count_entities(:insights, user_id) do
    Repo.aggregate(
      from(p in Post, where: p.is_deleted == false and p.user_id == ^user_id),
      :count,
      :id
    )
  end

  defp count_entities(:charts, user_id) do
    Repo.aggregate(
      from(c in Configuration, where: c.is_deleted == false and c.user_id == ^user_id),
      :count,
      :id
    )
  end

  defp count_entities(:screeners, user_id) do
    Repo.aggregate(
      from(ul in UserList,
        where: ul.is_deleted == false and ul.is_screener == true and ul.user_id == ^user_id
      ),
      :count,
      :id
    )
  end

  defp count_entities(:watchlists, user_id) do
    Repo.aggregate(
      from(ul in UserList,
        where: ul.is_deleted == false and ul.is_screener == false and ul.user_id == ^user_id
      ),
      :count,
      :id
    )
  end

  defp search_users(query) do
    query = String.trim(query)

    case Integer.parse(query) do
      {user_id, ""} ->
        # Numeric input — search by ID
        Repo.all(from(u in User, where: u.id == ^user_id, limit: 10))

      _ ->
        # Text input — search by username or email (case-insensitive partial match)
        pattern = "%#{String.downcase(query)}%"

        Repo.all(
          from(u in User,
            where:
              fragment("lower(?) LIKE ?", u.username, ^pattern) or
                fragment("lower(?) LIKE ?", u.email, ^pattern),
            order_by: u.id,
            limit: 10
          )
        )
    end
  end

  defp override_descriptions(:insights, user_id) do
    Repo.update_all(
      from(p in Post,
        where: p.user_id == ^user_id and p.is_deleted == false and not is_nil(p.ai_description),
        update: [set: [short_desc: p.ai_description]]
      ),
      []
    )
  end

  defp override_descriptions(:charts, user_id) do
    Repo.update_all(
      from(c in Configuration,
        where: c.user_id == ^user_id and c.is_deleted == false and not is_nil(c.ai_description),
        update: [set: [description: c.ai_description]]
      ),
      []
    )
  end

  defp override_descriptions(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    Repo.update_all(
      from(ul in UserList,
        where:
          ul.user_id == ^user_id and ul.is_deleted == false and ul.is_screener == ^screener_flag and
            not is_nil(ul.ai_description),
        update: [set: [description: ul.ai_description]]
      ),
      []
    )
  end

  defp update_entity_ai_desc(entities, id, ai_description) do
    Enum.map(entities, fn e ->
      if e.id == id, do: Map.put(e, :ai_description, ai_description), else: e
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — display helpers
  # ---------------------------------------------------------------------------

  defp entity_title(:insights, entity), do: entity.title || "(untitled)"
  defp entity_title(:charts, entity), do: entity.title || "(untitled)"
  defp entity_title(t, entity) when t in [:screeners, :watchlists], do: entity.name || "(unnamed)"

  defp entity_description(:insights, entity), do: entity.short_desc
  defp entity_description(:charts, entity), do: entity.description
  defp entity_description(t, entity) when t in [:screeners, :watchlists], do: entity.description

  defp entity_url(:insights, entity),
    do: SanbaseWeb.Endpoint.frontend_url() <> "/insights/read/#{entity.id}"

  defp entity_url(:charts, entity),
    do: SanbaseWeb.Endpoint.frontend_url() <> "/charts/-#{entity.id}"

  defp entity_url(:screeners, entity),
    do: SanbaseWeb.Endpoint.frontend_url() <> "/screener/#{entity.id}"

  defp entity_url(:watchlists, entity),
    do: SanbaseWeb.Endpoint.frontend_url() <> "/watchlist/projects/#{entity.id}"

  defp admin_resource(:insights), do: "posts"
  defp admin_resource(:charts), do: "chart_configurations"
  defp admin_resource(t) when t in [:screeners, :watchlists], do: "user_lists"

  defp user_display_name(user) do
    user.username || user.email || "user ##{user.id}"
  end

  defp truncate(nil, _len), do: ""
  defp truncate(str, len) when byte_size(str) <= len, do: str
  defp truncate(str, len), do: String.slice(str, 0, len) <> "…"

  defp parse_int(nil, default), do: default

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> max(1, n)
      _ -> default
    end
  end

  defp parse_int(v, _) when is_integer(v), do: max(1, v)
  defp parse_int(_, default), do: default

  defp parse_int_or_nil(nil), do: nil

  defp parse_int_or_nil(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp page_url(socket, page) do
    params = [page: page]

    params =
      if socket.assigns.selected_user,
        do: [user_id: socket.assigns.selected_user.id] ++ params,
        else: params

    ~p"/admin/ai_descriptions?#{params}"
  end

  defp maybe_load_user_from_param(socket, nil) do
    if socket.assigns.selected_user do
      socket
      |> assign(:selected_user, nil)
      |> assign(:search_query, "")
      |> assign(:custom_prompt, "")
      |> assign(:custom_prompt_error, nil)
      |> assign_custom_prompt_form("")
      |> assign(:entities, [])
      |> assign(:total_count, 0)
      |> assign(:total_pages, 1)
    else
      socket
    end
  end

  defp maybe_load_user_from_param(socket, user_id) do
    if socket.assigns.selected_user && socket.assigns.selected_user.id == user_id do
      socket
    else
      case Repo.get(User, user_id) do
        nil ->
          socket
          |> assign(:selected_user, nil)
          |> assign(:selected_entity, nil)
          |> assign(:entities, [])
          |> assign(:total_count, 0)
          |> assign(:total_pages, 1)
          |> put_flash(:error, "User not found")

        user ->
          prompt = UserSettings.get_ai_refinement_prompt(user.id) || ""

          socket
          |> assign(:selected_user, user)
          |> assign(:search_query, user_display_name(user))
          |> assign(:selected_entity, nil)
          |> assign(:custom_prompt, prompt)
          |> assign(:custom_prompt_error, nil)
          |> assign_custom_prompt_form(prompt)
      end
    end
  end

  defp assign_custom_prompt_form(socket, prompt) do
    assign(socket, :form, to_form(%{"custom_prompt" => prompt || ""}, as: :custom_prompt))
  end

  defp extract_custom_prompt_param(%{"custom_prompt" => %{"custom_prompt" => value}})
       when is_binary(value),
       do: value

  defp extract_custom_prompt_param(%{"custom_prompt" => value}) when is_binary(value), do: value
  defp extract_custom_prompt_param(_), do: ""

  defp effective_custom_prompt(prompt) when is_binary(prompt) do
    case String.trim(prompt) do
      "" -> DescriptionJob.default_refinement_prompt()
      _ -> prompt
    end
  end

  defp effective_custom_prompt(_), do: DescriptionJob.default_refinement_prompt()

  defp bulk_progress_pct(%{total: 0}), do: 0

  defp bulk_progress_pct(%{total: total, done: done, failed: failed}),
    do: round((done + failed) / total * 100)

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-full mx-auto">
      <h1 class="text-3xl font-bold mb-2">AI Description Generator</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Search for a user to view and generate AI descriptions for their charts, screeners, watchlists, and insights.
      </p>

      <%!-- ── User search ─────────────────────────────────────────── --%>
      <div class="mb-6 relative">
        <div class="flex items-center gap-3">
          <form phx-change="search_user" phx-submit="noop" class="flex-1 max-w-md">
            <label class="input input-sm w-full">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="text"
                name="query"
                value={@search_query}
                phx-debounce="200"
                placeholder="Search by username, email or user ID…"
                autocomplete="off"
              />
            </label>
          </form>
          <button :if={@selected_user} phx-click="clear_user" class="btn btn-sm btn-soft">
            Clear
          </button>
        </div>

        <%!-- Search dropdown --%>
        <ul
          :if={@search_results != []}
          class="menu menu-sm bg-base-100 rounded-box shadow border border-base-300 absolute z-20 mt-1 w-full max-w-md"
        >
          <li :for={user <- @search_results}>
            <button
              phx-click="select_user"
              phx-value-user_id={user.id}
              class="flex items-center justify-between gap-4"
            >
              <span class="text-sm font-medium">{user_display_name(user)}</span>
              <span class="text-xs text-base-content/50 shrink-0">
                id: {user.id}{if user.username && user.email, do: " · #{user.email}"}
              </span>
            </button>
          </li>
        </ul>

        <%!-- Selected user chip --%>
        <div :if={@selected_user} class="mt-2 flex items-center gap-2">
          <span class="badge badge-info badge-soft gap-2">
            <.icon name="hero-user" class="size-3" />
            {user_display_name(@selected_user)}
            <.link
              navigate={~p"/admin/generic/#{@selected_user.id}?resource=users"}
              class="link text-xs"
            >
              #{@selected_user.id}
            </.link>
          </span>
        </div>
      </div>

      <%!-- ── Empty state (no user selected) ────────────────────── --%>
      <div :if={is_nil(@selected_user)} class="mt-20 text-center text-base-content/40">
        <.icon name="hero-users" class="size-16 mx-auto mb-4 text-base-content/20" />
        <p class="text-lg font-medium">No user selected</p>
        <p class="text-sm mt-1">
          Search for a user by username, email, or ID to get started
        </p>
      </div>

      <%!-- ── Main UI (user selected) ────────────────────────────── --%>
      <div :if={@selected_user} class="space-y-5">
        <%!-- Global prompt (read-only) --%>
        <div class="card bg-base-200 border border-base-300 p-4">
          <label class="block text-sm font-medium mb-2">
            Global refinement prompt
            <span class="font-normal text-base-content/60">(read-only default prompt)</span>
          </label>
          <textarea readonly rows="4" class="textarea textarea-sm w-full resize-none">{@global_refinement_prompt}</textarea>
        </div>

        <%!-- Custom prompt --%>
        <div class="card bg-warning/10 border border-warning/30 p-4">
          <div class="mb-2">
            <span class="block text-sm font-medium">Refinement pass</span>
            <ul class="list-disc list-inside mt-1 space-y-0.5 text-sm font-normal text-base-content/70">
              <li>saved per user</li>
              <li>overrides Global refinement prompt</li>
              <li>leave empty if Global refinement prompt works ok</li>
            </ul>
          </div>
          <.form
            for={@form}
            phx-change="update_custom_prompt"
            phx-submit="save_custom_prompt"
            class="contents"
          >
            <.input
              type="textarea"
              field={@form[:custom_prompt]}
              phx-debounce="300"
              rows="2"
              placeholder="e.g. Focus on DeFi context. Use simpler language for beginners."
              class="textarea textarea-sm w-full resize-none"
            />
            <div class="mt-2 flex justify-end">
              <button type="submit" class="btn btn-sm btn-warning">
                Save refinement pass
              </button>
            </div>
          </.form>
          <p :if={@custom_prompt_error} class="mt-2 text-sm text-error">
            {@custom_prompt_error}
          </p>
        </div>

        <%!-- Tabs + Bulk actions --%>
        <div class="flex items-end justify-between border-b border-base-300">
          <div role="tablist" class="tabs tabs-border -mb-px">
            <button
              :for={
                {label, type} <- [
                  {"Charts", :charts},
                  {"Screeners", :screeners},
                  {"Watchlists", :watchlists},
                  {"Insights", :insights}
                ]
              }
              role="tab"
              phx-click="select_tab"
              phx-value-type={type}
              class={["tab", @entity_type == type && "tab-active"]}
            >
              {label}
              <span class={[
                "ml-1 badge badge-xs",
                if(@entity_type == type, do: "badge-primary", else: "badge-ghost")
              ]}>
                {Map.get(@tab_counts, type, 0)}
              </span>
            </button>
          </div>

          <%!-- Action buttons --%>
          <div class="flex gap-2 pb-3">
            <button
              phx-click="bulk_generate"
              disabled={not is_nil(@bulk_job) && @bulk_job.status == :running}
              class="btn btn-sm btn-primary"
            >
              <.icon name="hero-bolt" class="size-4" /> Bulk Generate
            </button>
            <button phx-click="show_override_confirm" class="btn btn-sm btn-soft btn-warning">
              Override Descriptions
            </button>
          </div>
        </div>

        <%!-- Bulk progress bar --%>
        <div :if={@bulk_job} class="card bg-base-100 border border-base-300 p-4">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <span class={[
                "inline-block w-2 h-2 rounded-full",
                if(@bulk_job.status == :running,
                  do: "bg-primary animate-pulse",
                  else: "bg-success"
                )
              ]} />
              <span class="text-sm font-medium">
                {if @bulk_job.status == :running, do: "Generating…", else: "Complete"}
              </span>
              <span class="text-xs text-base-content/60">
                {@bulk_job.done} done · {@bulk_job.failed} failed · {@bulk_job.total - @bulk_job.done -
                  @bulk_job.failed} remaining
              </span>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-sm font-semibold">{bulk_progress_pct(@bulk_job)}%</span>
              <button
                :if={@bulk_job.status == :running}
                phx-click="bulk_cancel"
                class="btn btn-xs btn-ghost text-error"
              >
                Cancel
              </button>
            </div>
          </div>
          <progress
            class={[
              "progress w-full",
              cond do
                @bulk_job.failed > 0 -> "progress-warning"
                @bulk_job.status == :cancelled -> "progress-neutral"
                true -> "progress-primary"
              end
            ]}
            value={bulk_progress_pct(@bulk_job)}
            max="100"
          >
          </progress>
          <div :if={@bulk_job.errors != []} class="mt-2 space-y-1">
            <p class="text-xs font-medium text-error">Failures:</p>
            <p :for={{id, reason} <- Enum.take(@bulk_job.errors, 5)} class="text-xs text-error">
              id #{id}: {reason}
            </p>
          </div>
        </div>

        <%!-- Stats row --%>
        <div class="text-xs text-base-content/60">
          Showing <span class="font-medium text-base-content">{length(@entities)}</span>
          of <span class="font-medium text-base-content">{@total_count}</span>
          · Page <span class="font-medium">{@page}</span>
          of <span class="font-medium">{@total_pages}</span>
        </div>

        <%!-- Table --%>
        <div class="rounded-box border border-base-300 overflow-hidden">
          <table class="table table-zebra table-sm table-fixed">
            <thead>
              <tr>
                <th class="w-40">Entity</th>
                <th>Current Description</th>
                <th>AI Description</th>
                <th class="w-24">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@entities == []}>
                <td colspan="4" class="text-center text-base-content/60 py-6">
                  No {to_string(@entity_type)} found for this user
                </td>
              </tr>
              <tr :for={entity <- @entities} id={"entity-#{entity.id}"}>
                <%!-- Entity --%>
                <td class="align-top">
                  <div class="flex flex-col gap-1">
                    <button
                      phx-click="select_entity"
                      phx-value-id={entity.id}
                      class="text-sm font-medium text-left link link-hover"
                    >
                      {truncate(entity_title(@entity_type, entity), 55)}
                    </button>
                    <div class="flex gap-2">
                      <a
                        href={entity_url(@entity_type, entity)}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="link link-primary text-xs"
                        phx-click="noop"
                      >
                        ↗ app
                      </a>
                      <.link
                        navigate={
                          ~p"/admin/generic/#{entity.id}?resource=#{admin_resource(@entity_type)}"
                        }
                        class="link text-xs text-base-content/60"
                      >
                        admin
                      </.link>
                    </div>
                    <div
                      :if={entity.ai_description}
                      class="w-2 h-2 rounded-full bg-success mt-0.5"
                      title="Has AI description"
                    />
                  </div>
                </td>

                <%!-- Current description --%>
                <td class="align-top">
                  <p class="text-xs text-base-content/70 whitespace-pre-wrap leading-relaxed">
                    {truncate(entity_description(@entity_type, entity), 100)}
                  </p>
                </td>

                <%!-- AI description --%>
                <td class="align-top">
                  <p class={[
                    "text-xs whitespace-pre-wrap leading-relaxed",
                    if(entity.ai_description, do: "text-success", else: "text-base-content/40 italic")
                  ]}>
                    {if entity.ai_description,
                      do: truncate(entity.ai_description, 100),
                      else: "not generated"}
                  </p>
                </td>

                <%!-- Actions --%>
                <td class="align-top">
                  <div class="flex flex-col gap-1.5">
                    <button
                      phx-click="generate"
                      phx-value-id={entity.id}
                      disabled={MapSet.member?(@loading_ids, entity.id)}
                      class="btn btn-xs btn-primary"
                    >
                      {if MapSet.member?(@loading_ids, entity.id),
                        do: "…",
                        else: if(entity.ai_description, do: "↺", else: "Generate")}
                    </button>
                    <button
                      phx-click="select_entity"
                      phx-value-id={entity.id}
                      class="btn btn-xs btn-soft"
                    >
                      View
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Pagination --%>
        <div :if={@total_pages > 1} class="flex items-center justify-between">
          <button phx-click="prev_page" disabled={@page == 1} class="btn btn-sm btn-soft">
            ← Previous
          </button>
          <span class="text-sm text-base-content/60">Page {@page} of {@total_pages}</span>
          <button
            phx-click="next_page"
            disabled={@page == @total_pages}
            class="btn btn-sm btn-soft"
          >
            Next →
          </button>
        </div>
      </div>
    </div>

    <%!-- ── Detail Modal ────────────────────────────────────────── --%>
    <div :if={@selected_entity} class="modal modal-open">
      <div class="modal-box max-w-3xl" phx-click="noop">
        <div class="flex items-center justify-between pb-4 border-b border-base-300">
          <div>
            <h2 class="text-lg font-semibold">
              {entity_title(@entity_type, @selected_entity)}
            </h2>
            <div class="flex gap-3 mt-1">
              <a
                href={entity_url(@entity_type, @selected_entity)}
                target="_blank"
                rel="noopener noreferrer"
                class="link link-primary text-xs"
              >
                ↗ View in app
              </a>
              <.link
                navigate={
                  ~p"/admin/generic/#{@selected_entity.id}?resource=#{admin_resource(@entity_type)}"
                }
                class="link text-xs text-base-content/60"
              >
                Admin record
              </.link>
            </div>
          </div>
          <button phx-click="close_modal" class="btn btn-sm btn-ghost btn-circle">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="pt-5 space-y-5">
          <div>
            <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-2">
              Current Description
            </h3>
            <div class="bg-base-200 rounded-box p-3 text-sm whitespace-pre-wrap min-h-10">
              {entity_description(@entity_type, @selected_entity) || "(no description)"}
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                AI Description
              </h3>
              <button
                phx-click="generate_selected"
                disabled={MapSet.member?(@loading_ids, @selected_entity.id)}
                class="btn btn-sm btn-primary"
              >
                {if MapSet.member?(@loading_ids, @selected_entity.id),
                  do: "Generating…",
                  else: if(@selected_entity.ai_description, do: "↺ Regenerate", else: "Generate")}
              </button>
            </div>
            <div class={[
              "rounded-box p-3 text-sm whitespace-pre-wrap min-h-12 font-mono leading-relaxed border",
              if(@selected_entity.ai_description,
                do: "bg-success/10 text-success-content border-success/30",
                else: "bg-base-200 text-base-content/50 border-dashed border-base-300"
              )
            ]}>
              {if MapSet.member?(@loading_ids, @selected_entity.id),
                do: "Generating…",
                else: @selected_entity.ai_description || "(not yet generated)"}
            </div>
          </div>

          <details class="text-xs text-base-content/60">
            <summary class="cursor-pointer hover:text-base-content font-medium select-none">
              Show input sent to LLM
            </summary>
            <pre class="mt-2 mockup-code bg-neutral text-neutral-content rounded-box p-3 text-xs overflow-auto whitespace-pre-wrap"><%= DescriptionJob.build_user_message(@selected_entity, @entity_type) %></pre>
          </details>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>

    <%!-- ── Override Confirmation Modal ──────────────────────────── --%>
    <div :if={@show_override_confirm} class="modal modal-open">
      <div class="modal-box max-w-md" phx-click="noop">
        <div class="flex items-start gap-3 mb-4">
          <div class="shrink-0 size-10 bg-warning/20 rounded-full flex items-center justify-center">
            <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
          </div>
          <div>
            <h3 class="text-base font-semibold">Override descriptions?</h3>
            <p class="text-sm text-base-content/70 mt-1">
              This will <strong>permanently replace</strong>
              the existing <code class="kbd kbd-xs">description</code>
              field with the <code class="kbd kbd-xs">ai_description</code>
              for all <span class="font-medium">{to_string(@entity_type)}</span>
              owned by
              <span class="font-medium">{@selected_user && user_display_name(@selected_user)}</span>
              that have an AI description set.
            </p>
            <p class="text-xs text-error mt-2 font-medium">
              ⚠ This cannot be undone.
            </p>
          </div>
        </div>
        <div class="modal-action">
          <button phx-click="hide_override_confirm" class="btn btn-sm btn-soft">
            Cancel
          </button>
          <button phx-click="confirm_override" class="btn btn-sm btn-warning">
            Yes, override descriptions
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="hide_override_confirm"></div>
    </div>
    """
  end
end
