defmodule SanbaseWeb.AskLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.Admin.FaqLive.Nav, only: [nav: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer: "",
       sources: %{faq: true, academy: true, insight: true},
       answer_log_link: nil,
       loading: nil,
       ask_meta: nil
     )}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ["ask_ai", "smart_search"] do
    question = socket.assigns.question
    sources = socket.assigns.sources

    cond do
      socket.assigns.loading != nil ->
        {:noreply, socket}

      Enum.any?(Map.values(sources), &(&1 == true)) ->
        function = if event == "ask_ai", do: :answer_question, else: :smart_search

        # Run the (slow) retrieval/LLM call off the LiveView process. Blocking it
        # here makes the socket miss heartbeats on long answers, so the client
        # reconnects and remounts to a fresh state, losing the answer.
        {:noreply,
         socket
         |> assign(:loading, event)
         |> assign(:answer, "")
         |> assign(:answer_log_link, nil)
         |> assign(:ask_meta, %{event: event, question: question, sources: sources})
         |> start_async(:ask_question, fn ->
           apply(Sanbase.Knowledge, function, [question, Keyword.new(sources)])
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
    sources = socket.assigns.sources

    updated_sources =
      Map.update!(sources, String.to_existing_atom(source), &(!&1))

    {:noreply, assign(socket, :sources, updated_sources)}
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

          <div class="mb-6 flex flex-wrap gap-6 justify-center">
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

  @impl true
  def handle_async(:ask_question, {:ok, result}, socket) do
    %{event: event, question: question, sources: sources} = socket.assigns.ask_meta
    current_user = socket.assigns.current_user

    socket =
      case result do
        {:ok, formatted_answer} ->
          log_async(event, current_user, question, formatted_answer, sources, true, "")
          assign(socket, :answer, formatted_answer)

        {:error, error} ->
          log_async(event, current_user, question, "<no answer> ", sources, false, error)
          require Logger
          Logger.debug("Ask error: #{inspect(error)}")
          assign(socket, :answer, "Can't answer. Please try again.")
      end

    {:noreply, assign(socket, :loading, nil)}
  end

  def handle_async(:ask_question, {:exit, reason}, socket) do
    require Logger
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

  defp log_async(question_type, current_user, question, answer, sources, is_successful, errors) do
    self = self()
    reranker = Sanbase.Knowledge.Reranker.label(Sanbase.Knowledge.Reranker.default_impl())

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
               reranker: reranker
             }) do
        url = Path.join([SanbaseWeb.Endpoint.admin_url(), "admin", "faq", "history", struct.id])
        send(self, {:populate_answer_log_link, url})
      end
    end)
  end
end
