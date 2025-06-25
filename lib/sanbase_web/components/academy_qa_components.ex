defmodule SanbaseWeb.AcademyQAComponents do
  use Phoenix.Component
  import Phoenix.HTML

  @doc """
  Renders the Academy Q&A header
  """
  attr :title, :string, default: "Academy Q&A"

  def academy_header(assigns) do
    ~H"""
    <div class="flex justify-between items-center mb-6">
      <div>
        <h2 class="text-2xl font-bold text-gray-900">{@title}</h2>
        <p class="text-sm text-gray-600 mt-1">
          Ask questions about Santiment and get answers from our Academy knowledge base
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the question input form
  """
  attr :question, :string, required: true
  attr :loading, :boolean, default: false

  def question_form(assigns) do
    ~H"""
    <form phx-submit="ask_question" class="space-y-4">
      <div class="flex gap-3">
        <div class="flex-1">
          <input
            type="text"
            name="question"
            value={@question}
            placeholder="Ask a question about Santiment..."
            class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={@loading}
          />
        </div>
        <button
          type="submit"
          disabled={@loading}
          class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium py-3 px-6 rounded-lg transition-colors"
        >
          {if @loading, do: "Asking...", else: "Ask"}
        </button>
        <button
          :if={@question != ""}
          type="button"
          phx-click="clear_question"
          class="bg-gray-500 hover:bg-gray-600 text-white font-medium py-3 px-4 rounded-lg transition-colors"
        >
          Clear
        </button>
      </div>
    </form>
    """
  end

  @doc """
  Renders the answer display with markdown content
  """
  attr :answer_data, :map, required: true

  def answer_display(assigns) do
    ~H"""
    <div class="border rounded-lg p-6 bg-white shadow-sm">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-gray-900">Answer</h3>
        <div class="flex items-center gap-4">
          <span class={[
            "text-xs px-2 py-1 rounded-full font-medium",
            confidence_class(@answer_data["confidence"])
          ]}>
            {String.upcase(@answer_data["confidence"] || "unknown")} CONFIDENCE
          </span>
          <span class="text-xs text-gray-500">
            {format_time(@answer_data["total_time_ms"])}
          </span>
        </div>
      </div>

      <div class="prose prose-sm max-w-none text-gray-800 prose-headings:text-gray-900 prose-strong:text-gray-900 prose-a:text-blue-600 prose-a:no-underline hover:prose-a:underline prose-ol:list-decimal prose-ul:list-disc prose-li:my-1">
        {raw(markdown_to_html(@answer_data["answer"]))}
      </div>
    </div>
    """
  end

  @doc """
  Renders the sources section with toggle functionality
  """
  attr :sources, :list, default: []
  attr :show_sources, :boolean, default: false

  attr :total_time_ms, :integer, default: 0

  def sources_section(assigns) do
    ~H"""
    <div class="border rounded-lg bg-white shadow-sm">
      <button
        phx-click="toggle_sources"
        class="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div class="flex items-center gap-3">
          <h3 class="text-lg font-semibold text-gray-900">Sources</h3>
          <span class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full font-medium">
            {length(@sources)} sources
          </span>
        </div>
        <svg
          class={["w-5 h-5 transition-transform", if(@show_sources, do: "rotate-180", else: "")]}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7">
          </path>
        </svg>
      </button>

      <div :if={@show_sources} class="px-6 pb-6 space-y-3">
        <.source_item :for={source <- @sources} source={source} />

        <div class="mt-4 pt-4 border-t border-gray-200">
          <div class="flex items-center justify-center text-xs text-gray-500">
            <span>Response time: {format_time(@total_time_ms)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single source item
  """
  attr :source, :map, required: true

  def source_item(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4">
      <div class="flex items-start justify-between mb-2">
        <div class="flex items-center gap-2">
          <span class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full font-medium">
            [{@source["number"]}]
          </span>
          <h4 class="font-medium text-gray-900">{@source["title"]}</h4>
        </div>
        <div class="flex items-center gap-2 text-xs text-gray-500">
          <span>{Float.round(@source["similarity"] * 100, 1)}% match</span>
        </div>
      </div>

      <a
        href={@source["url"]}
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm text-blue-600 hover:text-blue-800 hover:underline flex items-center gap-1"
      >
        <span>{@source["url"]}</span>
        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
            clip-rule="evenodd"
          >
          </path>
        </svg>
      </a>
    </div>
    """
  end

  # Helper functions
  defp confidence_class("high"), do: "bg-green-100 text-green-800"
  defp confidence_class("medium"), do: "bg-yellow-100 text-yellow-800"
  defp confidence_class("low"), do: "bg-red-100 text-red-800"
  defp confidence_class(_), do: "bg-gray-100 text-gray-800"

  defp format_time(nil), do: "N/A"
  defp format_time(ms) when is_integer(ms), do: "#{Float.round(ms / 1000, 1)}s"
  defp format_time(_), do: "N/A"

  defp markdown_to_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _} -> html
      {:error, _html, _errors} -> markdown
      _ -> markdown
    end
  end

  defp markdown_to_html(_), do: ""
end
