defmodule SanbaseWeb.AskLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer: "",
       sources: %{faq: true, academy: true, insights: true}
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
        case apply(Sanbase.Knowledge.Faq, function, [question, Keyword.new(sources)]) do
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

            # TODO: Do not log the error when making this public-facing
            socket
            |> assign(:answer, "Can't answer. Got error: #{inspect(error)}")
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
    updated_sources = Map.update!(sources, String.to_existing_atom(source), &(!&1))
    {:noreply, assign(socket, :sources, updated_sources)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center bg-white">
      <div class="w-full max-w-3xl flex flex-col items-center mt-10">
        <form class="w-full">
          <input
            name="question"
            type="text"
            autofocus
            value={@question}
            placeholder="Ask a question..."
            phx-change="update_question"
            class="border border-gray-300 rounded-lg shadow w-full text-base px-8 py-6 mb-4 focus:outline-none focus:ring-2 focus:ring-blue-400 bg-white max-w-3xl"
          />

          <div class="mb-6 flex flex-wrap gap-6 justify-center">
            <label class="flex items-center space-x-2 cursor-pointer">
              <input
                type="checkbox"
                name="faq"
                value="true"
                checked={@sources.faq}
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
              />
              <span class="text-sm font-medium text-gray-700">FAQ</span>
            </label>

            <label class="flex items-center space-x-2 cursor-pointer">
              <input
                type="checkbox"
                name="academy"
                value="true"
                checked={@sources.academy}
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
              />
              <span class="text-sm font-medium text-gray-700">Academy</span>
            </label>

            <label class="flex items-center space-x-2 cursor-pointer">
              <input
                type="checkbox"
                name="insights"
                value="true"
                checked={@sources.insights}
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
              />
              <span class="text-sm font-medium text-gray-700">Insights</span>
            </label>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              phx-click="smart_search"
              class="flex-1 bg-green-600 hover:bg-green-700 transition text-white text-xl px-6 py-4 rounded-lg font-semibold shadow"
              phx-disable-with="Searching..."
            >
              Smart Search
            </button>
            <button
              type="submit"
              phx-click="ask_ai"
              class="flex-1 bg-blue-600 hover:bg-blue-700 transition text-white text-xl px-6 py-4 rounded-lg font-semibold shadow"
              phx-disable-with="Answering..."
            >
              Ask Santiment AI
            </button>
          </div>
        </form>
        <%= if @answer != "" do %>
          <div class="mt-10 w-full flex flex-col items-center">
            <div class="bg-gray-100 rounded-lg shadow p-10 w-full max-w-3xl flex flex-col">
              <h3 class="text-2xl font-bold mb-6">Answer</h3>
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

  defp log_async(question_type, current_user, question, answer, sources, is_successful, errors) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Knowledge.QuestionAnswerLog.create(%{
        question: question,
        question_type: question_type,
        answer: answer,
        source: Enum.filter(Map.keys(sources), &Map.get(sources, &1)) |> Enum.join(", "),
        is_successful: is_successful,
        user_id: current_user && current_user.id,
        errors: inspect(errors)
      })
    end)
  end
end
