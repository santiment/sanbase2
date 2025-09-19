defmodule SanbaseWeb.AskLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, question: "", answer: "")}
  end

  @impl true
  def handle_event("ask", %{"question" => question}, socket) do
    socket =
      case Sanbase.Knowledge.Faq.answer_question(question) do
        {:ok, formatted_answer} ->
          socket
          |> assign(:question, question)
          |> assign(:answer, formatted_answer)

        _ ->
          socket
          |> assign(:question, question)
          |> assign(:answer, "Sorry, I don't have an answer for that question.")
      end

    {:noreply, socket}
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

              {Phoenix.HTML.raw(Earmark.as_html!(@answer))}
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
