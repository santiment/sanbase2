defmodule SanbaseWeb.Admin.PromoTrialLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  alias Sanbase.Billing.Subscription.PromoTrial

  @page_size 20
  @day_steps [7, 30]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Promo Trials")
     |> assign(:page_size, @page_size)
     |> assign(:day_steps, @day_steps)
     |> assign(:editing_id, nil)
     |> assign(:edit_days, nil)
     |> assign(:confirm, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = params |> Map.get("page") |> parse_int(1) |> max(1)
    search = Map.get(params, "search", "")

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:search, search)
     |> load_rows()}
  end

  @impl true
  def handle_event("search", %{"value" => search}, socket) do
    {:noreply, push_patch(socket, to: index_path(search, 1))}
  end

  def handle_event("goto_page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: index_path(socket.assigns.search, parse_int(page, 1)))}
  end

  def handle_event("edit_days", %{"id" => id}, socket) do
    id = parse_int(id, nil)
    row = find_row(socket, id)

    case row do
      nil ->
        {:noreply, socket}

      row ->
        {:noreply,
         socket |> assign(:editing_id, id) |> assign(:edit_days, row.promo_trial.trial_days)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_id, nil) |> assign(:edit_days, nil)}
  end

  def handle_event("set_days", %{"value" => value}, socket) do
    case parse_int(value, nil) do
      days when is_integer(days) and days > 0 and days <= 3650 ->
        {:noreply, assign(socket, :edit_days, days)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("shift_days", %{"days" => days}, socket) do
    days = parse_int(days, 0)
    new_days = (socket.assigns.edit_days || 0) + days

    {:noreply, assign(socket, :edit_days, new_days |> max(1) |> min(3650))}
  end

  def handle_event("save_days", %{"id" => id}, socket) do
    row = find_row(socket, parse_int(id, nil))
    days = socket.assigns.edit_days

    case {row, days} do
      {nil, _} ->
        {:noreply, socket}

      {row, days} when is_integer(days) and days > 0 ->
        case PromoTrial.update_trial_days(row.promo_trial, days) do
          {:ok, promo_trial} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Trial is now #{promo_trial.trial_days} days, ending #{format_datetime(PromoTrial.trial_end_for(promo_trial, promo_trial.trial_days))}."
             )
             |> assign(:editing_id, nil)
             |> assign(:edit_days, nil)
             |> load_rows()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, error_message(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Enter a trial length of at least 1 day.")}
    end
  end

  def handle_event("confirm_cancel_all", %{"id" => id}, socket) do
    case find_row(socket, parse_int(id, nil)) do
      nil ->
        {:noreply, socket}

      row ->
        active = Enum.reject(row.subscriptions, &(&1.status == :canceled))

        {:noreply,
         assign(socket, :confirm, %{
           type: :cancel_all,
           id: row.promo_trial.id,
           title: "Cancel #{length(active)} subscription(s)?",
           details: "#{user_label(row.promo_trial.user)} loses access immediately."
         })}
    end
  end

  def handle_event("confirm_cancel_subscription", %{"id" => id}, socket) do
    id = parse_int(id, nil)

    case find_subscription(socket, id) do
      nil ->
        {:noreply, socket}

      subscription ->
        {:noreply,
         assign(socket, :confirm, %{
           type: :cancel_subscription,
           id: id,
           title: "Cancel #{plan_label(subscription)}?",
           details: "The subscription is cancelled in Stripe immediately."
         })}
    end
  end

  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  def handle_event("do_confirmed", _params, socket) do
    socket = run_confirmed(socket, socket.assigns.confirm)

    {:noreply, socket |> assign(:confirm, nil) |> load_rows()}
  end

  defp run_confirmed(socket, %{type: :cancel_all, id: id}) do
    case find_row(socket, id) do
      nil ->
        socket

      row ->
        case PromoTrial.cancel_subscriptions(row.promo_trial) do
          {:ok, count} -> put_flash(socket, :info, "Cancelled #{count} subscription(s).")
          {:error, reason} -> put_flash(socket, :error, error_message(reason))
        end
    end
  end

  defp run_confirmed(socket, %{type: :cancel_subscription, id: id}) do
    case find_subscription(socket, id) do
      nil ->
        socket

      subscription ->
        case PromoTrial.cancel_subscription(subscription) do
          {:ok, _} -> put_flash(socket, :info, "Cancelled #{plan_label(subscription)}.")
          {:error, reason} -> put_flash(socket, :error, error_message(reason))
        end
    end
  end

  defp run_confirmed(socket, _), do: socket

  defp load_rows(socket) do
    %{page: page, page_size: page_size, search: search} = socket.assigns

    {rows, total} =
      PromoTrial.list_with_subscriptions(page: page, page_size: page_size, search: search)

    socket
    |> assign(:rows, rows)
    |> assign(:total, total)
    |> assign(:pages, ceil(total / page_size))
  end

  defp find_row(_socket, nil), do: nil
  defp find_row(socket, id), do: Enum.find(socket.assigns.rows, &(&1.promo_trial.id == id))

  defp find_subscription(_socket, nil), do: nil

  defp find_subscription(socket, id) do
    socket.assigns.rows
    |> Enum.flat_map(& &1.subscriptions)
    |> Enum.find(&(&1.id == id))
  end

  defp index_path(search, page) do
    params =
      %{}
      |> then(fn params ->
        if search in [nil, ""], do: params, else: Map.put(params, "search", search)
      end)
      |> then(fn params -> if page <= 1, do: params, else: Map.put(params, "page", page) end)

    ~p"/admin/promo_trials?#{params}"
  end

  defp user_label(nil), do: "(no user)"
  defp user_label(user), do: user.email || user.username || "user ##{user.id}"

  defp plan_label(%{plan: %{product: product} = plan}), do: "#{product.name} / #{plan.name}"
  defp plan_label(%{id: id}), do: "subscription ##{id}"

  defp format_datetime(nil), do: "-"

  defp format_datetime(%NaiveDateTime{} = naive),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> format_datetime()

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(%Stripe.Error{message: message}), do: message
  defp error_message(reason), do: inspect(reason)

  defp status_class(:trialing), do: "badge-info"
  defp status_class(:active), do: "badge-success"
  defp status_class(:canceled), do: "badge-ghost"
  defp status_class(:past_due), do: "badge-error"
  defp status_class(_), do: "badge-warning"

  defp trialing_count(subscriptions), do: Enum.count(subscriptions, &(&1.status == :trialing))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-200/40 min-h-full">
      <div class="max-w-7xl mx-auto px-6 py-8 space-y-6">
        <nav class="text-sm breadcrumbs">
          <ul>
            <li><.link navigate={~p"/admin"} class="link-hover">Admin</.link></li>
            <li class="text-base-content/60">Promo Trials</li>
          </ul>
        </nav>

        <header class="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight">Promo trials</h1>
            <p class="text-sm text-base-content/60 mt-1 max-w-3xl">
              Granted trials and the Stripe subscriptions behind them. Changing the trial length or
              cancelling is applied in Stripe right away.
            </p>
          </div>
          <.link navigate={~p"/admin/promo_trials/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Grant promo trial
          </.link>
        </header>

        <div class="flex items-center gap-3 flex-wrap">
          <label class="input input-sm w-80">
            <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
            <input
              type="text"
              value={@search}
              phx-keyup="search"
              phx-debounce="300"
              placeholder="email, username, user id or promo trial id"
              autocomplete="off"
            />
          </label>
          <span class="text-sm text-base-content/60 tabular-nums">{@total} promo trials</span>
        </div>

        <div class="overflow-x-auto card bg-base-100 border border-base-300 shadow-xs">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>ID</th>
                <th>User</th>
                <th>Granted</th>
                <th>Trial length</th>
                <th>Subscriptions</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@rows == []}>
                <td colspan="6" class="text-center italic text-base-content/50 py-6">
                  No promo trials match.
                </td>
              </tr>
              <tr :for={row <- @rows} class="align-top">
                <td class="font-mono text-xs">{row.promo_trial.id}</td>
                <td>
                  <.link
                    navigate={~p"/admin/generic/#{row.promo_trial.user_id}?resource=users"}
                    class="link link-primary"
                  >
                    {user_label(row.promo_trial.user)}
                  </.link>
                  <div class="text-xs text-base-content/50 font-mono">
                    #{row.promo_trial.user_id}
                  </div>
                </td>
                <td class="whitespace-nowrap text-xs">
                  {format_datetime(row.promo_trial.inserted_at)}
                </td>
                <td>
                  <div :if={@editing_id != row.promo_trial.id}>
                    <span class="font-medium tabular-nums">{row.promo_trial.trial_days} days</span>
                    <div class="text-xs text-base-content/50 whitespace-nowrap">
                      ends {format_datetime(
                        PromoTrial.trial_end_for(row.promo_trial, row.promo_trial.trial_days)
                      )}
                    </div>
                  </div>

                  <div :if={@editing_id == row.promo_trial.id} class="space-y-2">
                    <div class="flex items-center gap-1">
                      <button
                        :for={d <- @day_steps}
                        type="button"
                        phx-click="shift_days"
                        phx-value-days={-d}
                        class="btn btn-xs btn-ghost border border-base-300 tabular-nums"
                      >
                        -{d}d
                      </button>
                      <label class="input input-xs w-20">
                        <input
                          type="number"
                          min="1"
                          max="3650"
                          value={@edit_days}
                          phx-keyup="set_days"
                          phx-debounce="300"
                          class="text-right tabular-nums"
                        />
                      </label>
                      <button
                        :for={d <- @day_steps}
                        type="button"
                        phx-click="shift_days"
                        phx-value-days={d}
                        class="btn btn-xs btn-ghost border border-base-300 tabular-nums"
                      >
                        +{d}d
                      </button>
                    </div>
                    <div class="text-xs text-base-content/60 whitespace-nowrap">
                      new end: {format_datetime(
                        PromoTrial.trial_end_for(row.promo_trial, @edit_days || 1)
                      )}
                    </div>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        phx-click="save_days"
                        phx-value-id={row.promo_trial.id}
                        phx-disable-with="Saving..."
                        class="btn btn-xs btn-primary"
                      >
                        Save to Stripe
                      </button>
                      <button type="button" phx-click="cancel_edit" class="btn btn-xs btn-ghost">
                        Cancel
                      </button>
                    </div>
                  </div>
                </td>
                <td>
                  <p :if={row.subscriptions == []} class="text-xs italic text-base-content/50">
                    No linked subscriptions ({Enum.join(row.promo_trial.plans, ", ")})
                  </p>
                  <ul class="space-y-1">
                    <li
                      :for={subscription <- row.subscriptions}
                      class="flex items-center gap-2 flex-wrap text-xs"
                    >
                      <span class={["badge badge-xs", status_class(subscription.status)]}>
                        {subscription.status}
                      </span>
                      <span class="font-medium">{plan_label(subscription)}</span>
                      <span class="text-base-content/50">
                        trial end {format_datetime(subscription.trial_end)}
                      </span>
                      <span class="font-mono text-base-content/40">{subscription.stripe_id}</span>
                      <button
                        :if={subscription.status != :canceled}
                        type="button"
                        phx-click="confirm_cancel_subscription"
                        phx-value-id={subscription.id}
                        class="btn btn-xs btn-ghost text-error"
                      >
                        Cancel
                      </button>
                    </li>
                  </ul>
                </td>
                <td class="text-right whitespace-nowrap">
                  <button
                    :if={@editing_id != row.promo_trial.id}
                    type="button"
                    phx-click="edit_days"
                    phx-value-id={row.promo_trial.id}
                    disabled={trialing_count(row.subscriptions) == 0}
                    title={
                      if(trialing_count(row.subscriptions) == 0,
                        do: "No trialing subscriptions left to change",
                        else: nil
                      )
                    }
                    class="btn btn-xs btn-ghost border border-base-300"
                  >
                    <.icon name="hero-pencil-square" class="size-3.5" /> Trial days
                  </button>
                  <button
                    :if={Enum.any?(row.subscriptions, &(&1.status != :canceled))}
                    type="button"
                    phx-click="confirm_cancel_all"
                    phx-value-id={row.promo_trial.id}
                    class="btn btn-xs btn-ghost text-error"
                  >
                    <.icon name="hero-x-circle" class="size-3.5" /> Cancel all
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@pages > 1} class="flex items-center justify-center gap-2">
          <button
            type="button"
            phx-click="goto_page"
            phx-value-page={@page - 1}
            disabled={@page <= 1}
            class="btn btn-sm btn-ghost border border-base-300"
          >
            Previous
          </button>
          <span class="text-sm tabular-nums">Page {@page} / {@pages}</span>
          <button
            type="button"
            phx-click="goto_page"
            phx-value-page={@page + 1}
            disabled={@page >= @pages}
            class="btn btn-sm btn-ghost border border-base-300"
          >
            Next
          </button>
        </div>
      </div>

      <div :if={@confirm} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-semibold text-lg">{@confirm.title}</h3>
          <p class="py-3 text-sm text-base-content/70">{@confirm.details}</p>
          <p class="text-sm text-base-content/70">
            This is applied in Stripe immediately and cannot be undone.
          </p>
          <div class="modal-action">
            <button type="button" phx-click="dismiss_confirm" class="btn btn-ghost btn-sm">
              Keep it
            </button>
            <button
              type="button"
              phx-click="do_confirmed"
              phx-disable-with="Cancelling..."
              class="btn btn-error btn-sm"
            >
              Cancel in Stripe
            </button>
          </div>
        </div>
        <div class="modal-backdrop bg-black/40" phx-click="dismiss_confirm"></div>
      </div>
    </div>
    """
  end
end
