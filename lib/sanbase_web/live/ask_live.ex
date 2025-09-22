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
  def handle_event("ask", %{"question" => question} = params, socket) do
    sources =
      %{
        faq: Map.get(params, "faq") == "true",
        academy: Map.get(params, "academy") == "true",
        insights: Map.get(params, "insights") == "true"
      }

    if Map.values(sources) |> Enum.any?(&(&1 == true)) do
      socket =
        case Sanbase.Knowledge.Faq.answer_question(question, Keyword.new(sources)) do
          {:ok, formatted_answer} ->
            socket
            |> assign(:question, question)
            |> assign(:answer, formatted_answer)
            |> assign(:sources, sources)

          {:error, error} ->
            socket
            |> assign(:question, question)
            # TODO: Do not log the error when making this public-facing
            |> assign(
              :answer,
              "Sorry, I don't have an answer for that question. Got error: #{inspect(error)}"
            )
            |> assign(:sources, sources)
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please select at least one source of information")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center bg-white">
      <div class="w-full max-w-3xl flex flex-col items-center mt-10">
        <form phx-submit="ask" class="w-full">
          <input
            name="question"
            type="text"
            autofocus
            value={@question}
            placeholder="Ask a question..."
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

          <button
            type="submit"
            class="w-full max-w-3xl bg-blue-600 hover:bg-blue-700 transition text-white text-xl px-6 py-4 rounded-lg font-semibold shadow"
            phx-disable-with="Answering..."
          >
            Ask
          </button>
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
end
