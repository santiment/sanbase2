defmodule SanbaseWeb.AskLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.Admin.FaqLive.Nav, only: [nav: 1]

  alias Sanbase.Knowledge.AnswerModel

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer: "",
       sources: %{faq: true, academy: true, insight: true},
       features: %{reranker: true, context_expansion: false},
       answer_model: AnswerModel.default_key(),
       answer_log_link: nil,
       loading: nil,
       ask_meta: nil
     )}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ["ask_ai", "smart_search"] do
    question = socket.assigns.question
    sources = socket.assigns.sources
    features = socket.assigns.features

    cond do
      socket.assigns.loading != nil ->
        {:noreply, socket}

      Enum.any?(Map.values(sources), &(&1 == true)) ->
        function = if event == "ask_ai", do: :answer_question, else: :smart_search

        reranker_mod =
          if features.reranker,
            do: Sanbase.Knowledge.Reranker.default_impl(),
            else: Sanbase.Knowledge.Reranker.Noop

        options =
          sources
          |> Keyword.new()
          |> Keyword.put(:reranker, reranker_mod)
          |> Keyword.put(:context_expansion, features.context_expansion)
          |> Keyword.merge(AnswerModel.options_for(socket.assigns.answer_model))

        # Only the AI answer path runs an LLM, so only it has a model to log;
        # smart search is pure retrieval.
        model = if event == "ask_ai", do: AnswerModel.resolve(options)

        # Run the (slow) retrieval/LLM call off the LiveView process. Blocking it
        # here makes the socket miss heartbeats on long answers, so the client
        # reconnects and remounts to a fresh state, losing the answer.
        {:noreply,
         socket
         |> assign(:loading, event)
         |> assign(:answer, "")
         |> assign(:answer_log_link, nil)
         |> assign(:ask_meta, %{
           event: event,
           question: question,
           sources: sources,
           reranker_mod: reranker_mod,
           context_expansion: features.context_expansion,
           model: model
         })
         |> start_async(:ask_question, fn ->
           apply(Sanbase.Knowledge, function, [question, options])
         end)}

      true ->
        {:noreply, put_flash(socket, :error, "Please select at least one source of information")}
    end
  end

  @impl true
  def handle_event("update_question", %{"question" => question}, socket) do
    {:noreply, assign(socket, :question, question)}
  end

  @impl true
  def handle_event("toggle_source", %{"source" => source}, socket) do
    {:noreply, assign(socket, :sources, toggle_flag(socket.assigns.sources, source))}
  end

  @impl true
  def handle_event("toggle_feature", %{"feature" => feature}, socket) do
    {:noreply, assign(socket, :features, toggle_flag(socket.assigns.features, feature))}
  end

  @impl true
  def handle_event("select_answer_model", %{"answer_model" => key}, socket) do
    # `key` comes from the client; ignore anything not in the current selectable
    # set so a bogus value can't be stored and later shown as the selected model.
    if Enum.any?(AnswerModel.selectable(), &(&1.key == key)) do
      {:noreply, assign(socket, :answer_model, key)}
    else
      {:noreply, socket}
    end
  end

  # Flip the boolean under the map key whose name matches `name`. `name` comes
  # from the client, so match it against the existing keys instead of
  # String.to_existing_atom/1 — an unknown value is ignored rather than crashing
  # the LiveView.
  defp toggle_flag(map, name) do
    case Enum.find(Map.keys(map), &(to_string(&1) == name)) do
      nil -> map
      key -> Map.update!(map, key, &(not &1))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.nav active={:ask} />
    <div class="flex flex-col items-center px-4">
      <div class="w-full max-w-3xl flex flex-col items-center mt-10">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold">Ask the Knowledge Base</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Search or get an AI answer from FAQ, Academy and Insights.
          </p>
        </div>
        <form class="w-full">
          <input
            name="question"
            type="text"
            autofocus
            value={@question}
            placeholder="Ask a question..."
            phx-change="update_question"
            class="input input-lg w-full mb-4"
          />

          <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
            <div class="flex flex-wrap gap-6">
              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  phx-click="toggle_source"
                  phx-value-source="faq"
                  name="faq"
                  value="true"
                  checked={@sources.faq}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm font-medium">FAQ</span>
              </label>

              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  phx-click="toggle_source"
                  phx-value-source="academy"
                  name="academy"
                  value="true"
                  checked={@sources.academy}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm font-medium">Academy</span>
              </label>

              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  phx-click="toggle_source"
                  phx-value-source="insight"
                  name="insight"
                  value="true"
                  checked={@sources.insight}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm font-medium">Insights</span>
              </label>
            </div>

            <div class="flex items-center gap-3">
              <.answer_model_select selected={@answer_model} />
              <.features_menu features={@features} />
            </div>
          </div>

          <div class="flex gap-4">
            <button
              type="button"
              phx-click="smart_search"
              class="btn btn-success btn-lg flex-1"
              disabled={@loading != nil}
            >
              <span :if={@loading == "smart_search"} class="loading loading-spinner loading-sm">
              </span>
              {if @loading == "smart_search", do: "Searching...", else: "Smart Search"}
            </button>
            <button
              type="button"
              phx-click="ask_ai"
              class="btn btn-primary btn-lg flex-1"
              disabled={@loading != nil}
            >
              <span :if={@loading == "ask_ai"} class="loading loading-spinner loading-sm"></span>
              {if @loading == "ask_ai", do: "Answering...", else: "Ask Santiment AI"}
            </button>
          </div>
        </form>
        <div :if={@answer != ""} class="mt-10 w-full flex flex-col items-center">
          <div class="card bg-base-200 shadow p-10 w-full max-w-3xl flex flex-col">
            <h3 class="text-2xl font-bold mb-6">Answer</h3>
            <.link
              :if={@answer_log_link}
              href={@answer_log_link}
              class="link link-primary font-bold"
            >
              {@answer_log_link}
            </.link>
            <div class="divider"></div>

            <div class="prose prose-lg max-w-none">
              {Phoenix.HTML.raw(Earmark.as_html!(@answer))}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Dropdown to pick which model answers (Ask AI only; smart search ignores it).
  # The choices come from `Sanbase.Knowledge.AnswerModel.selectable/0`.
  attr :selected, :string, required: true

  defp answer_model_select(assigns) do
    assigns = assign(assigns, :models, AnswerModel.selectable())

    ~H"""
    <label class="flex items-center gap-2">
      <span class="text-sm font-medium">Model</span>
      <select
        name="answer_model"
        phx-change="select_answer_model"
        class="select select-sm select-bordered"
      >
        <option :for={m <- @models} value={m.key} selected={m.key == @selected}>
          {m.label}
        </option>
      </select>
    </label>
    """
  end

  # Toggleable retrieval features surfaced in the "Features" dropdown. Add a
  # tuple here to expose a new on/off feature; the assign key must exist in the
  # `features` map set in mount/3.
  @feature_toggles [
    {:reranker, "Reranker", "Re-order retrieved results by relevance before answering."},
    {:context_expansion, "Context expansion",
     "Pull the neighbouring chunks around each match for fuller context (Ask only)."}
  ]

  attr :features, :map, required: true

  defp features_menu(assigns) do
    assigns = assign(assigns, :toggles, @feature_toggles)

    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-outline gap-1.5">
        <.icon name="hero-adjustments-horizontal" class="size-4" /> Features
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu z-10 mt-2 w-72 gap-1 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
      >
        <li :for={{key, label, hint} <- @toggles} class="p-0">
          <label class="flex items-start justify-between gap-3 cursor-pointer rounded-lg p-2">
            <span class="flex flex-col">
              <span class="text-sm font-medium">{label}</span>
              <span class="text-xs text-base-content/60">{hint}</span>
            </span>
            <input
              type="checkbox"
              phx-click="toggle_feature"
              phx-value-feature={key}
              checked={Map.get(@features, key)}
              class="toggle toggle-sm toggle-primary mt-0.5"
            />
          </label>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def handle_async(:ask_question, {:ok, result}, socket) do
    %{
      event: event,
      question: question,
      sources: sources,
      reranker_mod: reranker_mod,
      context_expansion: context_expansion,
      model: model
    } = socket.assigns.ask_meta

    current_user = socket.assigns.current_user

    socket =
      case result do
        {:ok, formatted_answer} ->
          log_async(
            event,
            current_user,
            question,
            formatted_answer,
            sources,
            true,
            "",
            reranker_mod,
            context_expansion,
            model
          )

          assign(socket, :answer, formatted_answer)

        {:error, error} ->
          log_async(
            event,
            current_user,
            question,
            "<no answer> ",
            sources,
            false,
            error,
            reranker_mod,
            context_expansion,
            model
          )

          Logger.debug("Ask error: #{inspect(error)}")
          assign(socket, :answer, "Can't answer. Please try again.")
      end

    {:noreply, assign(socket, :loading, nil)}
  end

  def handle_async(:ask_question, {:exit, reason}, socket) do
    Logger.error("Ask crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:answer, "Can't answer. Please try again.")
     |> assign(:loading, nil)}
  end

  @impl true
  def handle_info({:populate_answer_log_link, link}, socket) do
    {:noreply,
     socket
     |> assign(:answer_log_link, link)}
  end

  defp log_async(
         question_type,
         current_user,
         question,
         answer,
         sources,
         is_successful,
         errors,
         reranker_mod,
         context_expansion,
         model
       ) do
    self = self()
    reranker = Sanbase.Knowledge.Reranker.label(reranker_mod)

    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      with {:ok, struct} <-
             Sanbase.Knowledge.QuestionAnswerLog.create(%{
               question: question,
               question_type: question_type,
               answer: answer,
               source: Enum.filter(Map.keys(sources), &Map.get(sources, &1)) |> Enum.join(", "),
               is_successful: is_successful,
               user_id: current_user && current_user.id,
               errors: inspect(errors),
               reranker: reranker,
               context_expansion: context_expansion,
               model: model
             }) do
        url = Path.join([SanbaseWeb.Endpoint.admin_url(), "admin", "faq", "history", struct.id])
        send(self, {:populate_answer_log_link, url})
      end
    end)
  end
end
