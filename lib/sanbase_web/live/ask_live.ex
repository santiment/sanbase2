defmodule SanbaseWeb.AskLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer: "",
       sources: %{faq: true, academy: true, insights: true},
       answer_log_link: nil
     )}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ["ask_ai", "smart_search"] do
    question = socket.assigns.question
    sources = socket.assigns.sources
    current_user = socket.assigns.current_user

    if Map.values(sources) |> Enum.any?(&(&1 == true)) do
      function = if event == "ask_ai", do: :answer_question, else: :smart_search

      socket =
        case apply(Sanbase.Knowledge, function, [question, Keyword.new(sources)]) do
          {:ok, formatted_answer} ->
            log_async(
              _question_type = event,
              current_user,
              question,
              formatted_answer,
              sources,
              _is_successful = true,
              _errors = ""
            )

            socket
            |> assign(:answer, formatted_answer)

          {:error, error} ->
            log_async(
              _question_type = event,
              current_user,
              question,
              "<no answer> ",
              sources,
              _is_successful = false,
              _errors = error
            )

            require Logger
            Logger.debug("Ask error: #{inspect(error)}")

            socket
            |> assign(:answer, "Can't answer. Please try again.")
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please select at least one source of information")}
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
    <div class="min-h-screen flex flex-col items-center justify-center">
      <div class="w-full max-w-3xl flex flex-col items-center mt-10">
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
                phx-value-source="insights"
                name="insights"
                value="true"
                checked={@sources.insights}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="text-sm font-medium">Insights</span>
            </label>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              phx-click="smart_search"
              class="btn btn-success btn-lg flex-1"
              phx-disable-with="Searching..."
            >
              Smart Search
            </button>
            <button
              type="submit"
              phx-click="ask_ai"
              class="btn btn-primary btn-lg flex-1"
              phx-disable-with="Answering..."
            >
              Ask Santiment AI
            </button>
          </div>
        </form>
        <%= if @answer != "" do %>
          <div class="mt-10 w-full flex flex-col items-center">
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
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:populate_answer_log_link, link}, socket) do
    {:noreply,
     socket
     |> assign(:answer_log_link, link)}
  end

  defp log_async(question_type, current_user, question, answer, sources, is_successful, errors) do
    self = self()

    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      with {:ok, struct} <-
             Sanbase.Knowledge.QuestionAnswerLog.create(%{
               question: question,
               question_type: question_type,
               answer: answer,
               source: Enum.filter(Map.keys(sources), &Map.get(sources, &1)) |> Enum.join(", "),
               is_successful: is_successful,
               user_id: current_user && current_user.id,
               errors: inspect(errors)
             }) do
        url = Path.join([SanbaseWeb.Endpoint.admin_url(), "admin", "faq", "history", struct.id])
        send(self, {:populate_answer_log_link, url})
      end
    end)
  end
end
