defmodule SanbaseWeb.Admin.PromoTrialLive.Form do
  use SanbaseWeb, :live_view

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription.PromoTrial

  @day_presets [14, 30, 60, 90, 180, 365]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Promo Trial")
     |> assign(:plans, PromoTrial.plans_grouped())
     |> assign(:interval, "month")
     |> assign(:selected_plans, MapSet.new())
     |> assign(:trial_days, 14)
     |> assign(:user_query, "")
     |> assign(:user_matches, [])
     |> assign(:selected_user, nil)
     |> assign(:day_presets, @day_presets)}
  end

  @impl true
  def handle_event("search_user", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:user_query, query)
     |> assign(:user_matches, search_users(query))}
  end

  def handle_event("select_user", %{"id" => id}, socket) do
    case User.by_id(String.to_integer(id)) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:selected_user, user)
         |> assign(:user_query, user.email || "user##{user.id}")
         |> assign(:user_matches, [])}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_query, "")
     |> assign(:user_matches, [])}
  end

  def handle_event("set_interval", %{"interval" => interval}, socket)
      when interval in ["month", "year"] do
    {:noreply, assign(socket, :interval, interval)}
  end

  def handle_event("toggle_plan", %{"id" => id}, socket) do
    set = socket.assigns.selected_plans

    new_set =
      if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)

    {:noreply, assign(socket, :selected_plans, new_set)}
  end

  def handle_event("set_trial_days", %{"value" => value}, socket) do
    case Integer.parse(to_string(value)) do
      {n, _} when n > 0 and n <= 3650 -> {:noreply, assign(socket, :trial_days, n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("preset_days", %{"days" => days}, socket) do
    {:noreply, assign(socket, :trial_days, String.to_integer(days))}
  end

  def handle_event("submit", _params, socket) do
    %{selected_user: user, selected_plans: plans, trial_days: days} = socket.assigns

    cond do
      is_nil(user) ->
        {:noreply, put_flash(socket, :error, "Select a user first.")}

      MapSet.size(plans) == 0 ->
        {:noreply, put_flash(socket, :error, "Pick at least one plan.")}

      true ->
        attrs = %{user_id: user.id, plans: MapSet.to_list(plans), trial_days: days}

        case PromoTrial.create_promo_trial(attrs) do
          {:ok, subs} when is_list(subs) ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Created #{length(subs)} promo subscription(s) for #{user.email}."
             )
             |> push_navigate(to: ~p"/admin/generic?resource=promo_trials")}

          {:ok, _sub} ->
            {:noreply,
             socket
             |> put_flash(:info, "Created promo subscription for #{user.email}.")
             |> push_navigate(to: ~p"/admin/generic?resource=promo_trials")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
        end
    end
  end

  defp search_users(query) when byte_size(query) < 2, do: []

  defp search_users(query) do
    pattern = "%" <> query <> "%"

    from(u in User,
      where: ilike(u.email, ^pattern) or ilike(u.username, ^pattern),
      order_by: [desc: u.id],
      limit: 8,
      select: %{id: u.id, email: u.email, username: u.username}
    )
    |> Sanbase.Repo.all()
  end

  defp plans_for(plans, product, interval) do
    plans
    |> Map.get(product, %{})
    |> Map.get(interval, [])
    |> Enum.sort_by(& &1.id)
  end

  defp all_plan_id_name_map(plans) do
    plans
    |> Enum.flat_map(fn {_product, by_interval} ->
      Enum.flat_map(by_interval, fn {interval, plan_list} ->
        Enum.map(plan_list, fn p ->
          {Integer.to_string(p.id), %{name: p.name, interval: interval}}
        end)
      end)
    end)
    |> Map.new()
  end

  defp user_initial(%{email: email}) when is_binary(email) and email != "" do
    String.first(email) |> String.upcase()
  end

  defp user_initial(_), do: "?"

  defp step_done?(:user, assigns), do: not is_nil(assigns.selected_user)
  defp step_done?(:days, assigns), do: assigns.trial_days > 0
  defp step_done?(:plans, assigns), do: MapSet.size(assigns.selected_plans) > 0

  attr :n, :integer, required: true
  attr :done, :boolean, required: true

  defp step_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center justify-center w-5 h-5 rounded-full text-[11px] font-semibold leading-none shrink-0 self-start mt-0.5",
      if(@done,
        do: "bg-success/15 text-success ring-1 ring-success/40",
        else: "bg-base-200 text-base-content/60 ring-1 ring-base-300"
      )
    ]}>
      <.icon :if={@done} name="hero-check" class="w-3 h-3" />
      <span :if={!@done}>{@n}</span>
    </span>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:plan_map, all_plan_id_name_map(assigns.plans))
      |> assign(:can_submit?, not is_nil(assigns.selected_user) and MapSet.size(assigns.selected_plans) > 0)

    ~H"""
    <div class="bg-base-200/40 min-h-full">
      <div class="max-w-6xl mx-auto px-6 py-8 space-y-6">
        <nav class="text-sm breadcrumbs">
          <ul>
            <li>
              <.link navigate={~p"/admin"} class="link-hover">Admin</.link>
            </li>
            <li>
              <.link
                navigate={~p"/admin/generic?resource=promo_trials"}
                class="link-hover"
              >
                Promo Trials
              </.link>
            </li>
            <li class="text-base-content/60">New</li>
          </ul>
        </nav>

        <header class="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight">Grant promo trial</h1>
            <p class="text-sm text-base-content/60 mt-1 max-w-2xl">
              Issue free trial subscriptions to a user across one or more plans. Trial length applies
              uniformly to every selected plan.
            </p>
          </div>
          <.link
            navigate={~p"/admin/generic?resource=promo_trials"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.link>
        </header>

        <div class="grid lg:grid-cols-3 gap-6 items-start">
          <div class="lg:col-span-2 space-y-4">
            <section class="card bg-base-100 border border-base-300 shadow-xs">
              <div class="card-body p-5">
                <div class="flex items-center gap-3 mb-3">
                  <.step_badge n={1} done={step_done?(:user, assigns)} />
                  <div class="flex-1">
                    <h2 class="font-semibold">User</h2>
                    <p class="text-xs text-base-content/60">Search by email or username</p>
                  </div>
                </div>

                <div :if={@selected_user} class="flex items-center gap-3 p-3 bg-base-200/60 rounded-box border border-base-300">
                  <div class="avatar avatar-placeholder">
                    <div class="bg-primary text-primary-content rounded-full w-10 h-10">
                      <span class="text-sm font-semibold">{user_initial(@selected_user)}</span>
                    </div>
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="font-medium truncate">{@selected_user.email}</div>
                    <div class="text-xs text-base-content/60">
                      <span :if={@selected_user.username}>@{@selected_user.username} · </span>id: {@selected_user.id}
                    </div>
                  </div>
                  <button type="button" phx-click="clear_user" class="btn btn-ghost btn-sm">
                    <.icon name="hero-x-mark" class="size-4" /> Change
                  </button>
                </div>

                <div :if={!@selected_user} class="relative">
                  <label class="input w-full">
                    <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                    <input
                      type="text"
                      value={@user_query}
                      phx-keyup="search_user"
                      phx-debounce="200"
                      placeholder="email@example.com or username"
                      autocomplete="off"
                    />
                  </label>
                  <p
                    :if={@user_query != "" and byte_size(@user_query) < 2}
                    class="text-xs text-base-content/50 mt-1"
                  >
                    Type at least 2 characters to search.
                  </p>
                  <p
                    :if={byte_size(@user_query) >= 2 and @user_matches == []}
                    class="text-xs text-base-content/50 mt-1"
                  >
                    No users match.
                  </p>
                  <ul
                    :if={@user_matches != []}
                    class="menu absolute top-full left-0 right-0 mt-1 z-20 bg-base-100 border border-base-300 rounded-box shadow-xl max-h-72 overflow-y-auto p-1"
                  >
                    <li :for={u <- @user_matches}>
                      <button
                        type="button"
                        phx-click="select_user"
                        phx-value-id={u.id}
                        class="!grid grid-cols-[auto_1fr_auto] gap-3 items-center !py-2"
                      >
                        <span class="avatar avatar-placeholder">
                          <span class="bg-base-300 rounded-full w-7 h-7">
                            <span class="text-xs font-semibold">{user_initial(u)}</span>
                          </span>
                        </span>
                        <span class="min-w-0">
                          <span class="block font-medium truncate">{u.email || "(no email)"}</span>
                          <span :if={u.username} class="block text-xs opacity-60 truncate">@{u.username}</span>
                        </span>
                        <span class="text-xs opacity-50 font-mono">#{u.id}</span>
                      </button>
                    </li>
                  </ul>
                </div>
              </div>
            </section>

            <section class="card bg-base-100 border border-base-300 shadow-xs">
              <div class="card-body p-5">
                <div class="flex items-center gap-3 mb-3">
                  <.step_badge n={2} done={step_done?(:days, assigns)} />
                  <div class="flex-1">
                    <h2 class="font-semibold">Trial length</h2>
                    <p class="text-xs text-base-content/60">How long the trial runs (in days)</p>
                  </div>
                </div>

                <div class="flex items-center gap-2 flex-wrap">
                  <label class="input input-sm w-32">
                    <input
                      type="number"
                      min="1"
                      max="3650"
                      value={@trial_days}
                      phx-keyup="set_trial_days"
                      phx-debounce="300"
                      class="text-right tabular-nums"
                    />
                    <span class="opacity-60 text-xs">days</span>
                  </label>

                  <span class="text-base-content/40 text-xs px-1">or</span>

                  <div class="flex flex-wrap gap-1.5">
                    <button
                      :for={d <- @day_presets}
                      type="button"
                      phx-click="preset_days"
                      phx-value-days={d}
                      class={[
                        "btn btn-sm tabular-nums",
                        if(@trial_days == d,
                          do: "btn-primary",
                          else: "btn-ghost border border-base-300"
                        )
                      ]}
                    >
                      {d}d
                    </button>
                  </div>
                </div>
              </div>
            </section>

            <section class="card bg-base-100 border border-base-300 shadow-xs">
              <div class="card-body p-5">
                <div class="flex items-center gap-3 mb-3 flex-wrap">
                  <.step_badge n={3} done={step_done?(:plans, assigns)} />
                  <div class="flex-1 min-w-0">
                    <h2 class="font-semibold flex items-center gap-2 flex-wrap">
                      Plans
                      <span :if={MapSet.size(@selected_plans) > 0} class="badge badge-primary badge-sm">
                        {MapSet.size(@selected_plans)} selected
                      </span>
                    </h2>
                    <p class="text-xs text-base-content/60">Pick one or more plans for the trial</p>
                  </div>

                  <div role="tablist" class="tabs tabs-box tabs-sm">
                    <button
                      type="button"
                      role="tab"
                      phx-click="set_interval"
                      phx-value-interval="month"
                      class={["tab", if(@interval == "month", do: "tab-active", else: "")]}
                    >
                      Monthly
                    </button>
                    <button
                      type="button"
                      role="tab"
                      phx-click="set_interval"
                      phx-value-interval="year"
                      class={["tab", if(@interval == "year", do: "tab-active", else: "")]}
                    >
                      Yearly
                    </button>
                  </div>
                </div>

                <div class="grid md:grid-cols-2 gap-3">
                  <.plan_column
                    title="Sanbase"
                    plans={plans_for(@plans, :sanbase, @interval)}
                    selected={@selected_plans}
                  />
                  <.plan_column
                    title="SanAPI"
                    plans={plans_for(@plans, :api, @interval)}
                    selected={@selected_plans}
                  />
                </div>
              </div>
            </section>
          </div>

          <aside class="lg:col-span-1 lg:sticky lg:top-4 space-y-3">
            <div class="card bg-base-100 border border-base-300 shadow-xs">
              <div class="card-body p-5">
                <h3 class="font-semibold">Summary</h3>

                <dl class="text-sm divide-y divide-base-200">
                  <div class="grid grid-cols-3 gap-2 py-2">
                    <dt class="text-base-content/60">User</dt>
                    <dd class="col-span-2 truncate">
                      <span :if={@selected_user} class="font-medium">{@selected_user.email}</span>
                      <span :if={!@selected_user} class="italic text-base-content/50">Not selected</span>
                    </dd>
                  </div>
                  <div class="grid grid-cols-3 gap-2 py-2">
                    <dt class="text-base-content/60">Trial</dt>
                    <dd class="col-span-2 font-medium tabular-nums">{@trial_days} days</dd>
                  </div>
                  <div class="grid grid-cols-3 gap-2 py-2">
                    <dt class="text-base-content/60">Plans</dt>
                    <dd class="col-span-2">
                      <span :if={MapSet.size(@selected_plans) == 0} class="italic text-base-content/50">None</span>
                      <ul :if={MapSet.size(@selected_plans) > 0} class="space-y-0.5">
                        <li :for={id <- MapSet.to_list(@selected_plans)} class="flex items-center justify-between gap-2 text-xs">
                          <span class="truncate">{Map.get(@plan_map, id, %{name: id})[:name]}</span>
                          <span class="badge badge-ghost badge-xs">{Map.get(@plan_map, id, %{interval: "?"})[:interval]}</span>
                        </li>
                      </ul>
                    </dd>
                  </div>
                </dl>

                <button
                  type="button"
                  phx-click="submit"
                  phx-disable-with="Creating..."
                  disabled={!@can_submit?}
                  class="btn btn-primary w-full mt-4"
                >
                  <.icon name="hero-check" class="size-4" /> Create promo trial
                </button>

                <p class="text-xs text-base-content/60 mt-2 leading-relaxed">
                  Creates one Stripe trial subscription per selected plan. Trials end automatically after
                  the configured length.
                </p>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :plans, :list, required: true
  attr :selected, :any, required: true

  defp plan_column(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-box overflow-hidden">
      <div class="px-3 py-2 bg-base-200/60 border-b border-base-300">
        <h3 class="text-sm font-semibold">{@title}</h3>
      </div>
      <div class="p-2">
        <p :if={@plans == []} class="text-xs italic text-base-content/50 px-2 py-3">
          No plans for this interval.
        </p>
        <ul class="space-y-0.5">
          <li :for={p <- @plans}>
            <% has_stripe = is_binary(p.stripe_id) and p.stripe_id != "" %>
            <label
              title={if(has_stripe, do: nil, else: "No stripe_id — cannot be granted in this environment")}
              class={[
                "flex items-center gap-3 px-2 py-1.5 rounded transition-colors",
                if(has_stripe,
                  do: "cursor-pointer hover:bg-base-200/60",
                  else: "opacity-50 cursor-not-allowed"
                ),
                if(MapSet.member?(@selected, Integer.to_string(p.id)), do: "bg-primary/5", else: "")
              ]}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={MapSet.member?(@selected, Integer.to_string(p.id))}
                disabled={!has_stripe}
                phx-click="toggle_plan"
                phx-value-id={p.id}
              />
              <span class="text-sm flex-1 truncate">{p.name}</span>
              <.icon
                :if={!has_stripe}
                name="hero-exclamation-triangle"
                class="size-4 text-warning shrink-0"
              />
              <span class="text-xs text-base-content/40 font-mono">#{p.id}</span>
            </label>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
