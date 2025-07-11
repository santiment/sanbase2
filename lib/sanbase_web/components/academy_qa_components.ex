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
  Renders the keyword search form with autocomplete from search API
  """
  attr :keyword_query, :string, required: true
  attr :keyword_loading, :boolean, default: false
  attr :autocomplete_suggestions, :list, default: []
  attr :show_autocomplete, :boolean, default: false

  def keyword_search_form(assigns) do
    ~H"""
    <div class="relative">
      <form phx-submit="keyword_search" class="space-y-4">
        <div class="flex gap-3">
          <div class="flex-1 relative">
            <input
              type="text"
              name="keyword_query"
              value={@keyword_query}
              placeholder="Search Academy content by keywords..."
              class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
              disabled={@keyword_loading}
              phx-change="keyword_input_change"
              phx-blur="hide_autocomplete"
              autocomplete="off"
            />
            
    <!-- Autocomplete Dropdown with search results -->
            <div
              :if={@show_autocomplete && length(@autocomplete_suggestions) > 0}
              class="absolute z-50 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-xl max-h-96 overflow-y-auto"
            >
              <div class="p-2 text-xs text-gray-500 border-b border-gray-100">
                Press Enter to search "{@keyword_query}" or click a suggestion below:
              </div>
              <button
                :for={suggestion <- @autocomplete_suggestions}
                type="button"
                phx-click="select_autocomplete"
                phx-value-suggestion={suggestion["title"]}
                class="w-full text-left p-3 hover:bg-green-50 focus:bg-green-50 border-b border-gray-100 last:border-b-0 group"
              >
                <div class="flex items-start gap-3">
                  <div class="flex-1">
                    <!-- Breadcrumb -->
                    <div class="text-xs text-gray-500 mb-1">
                      {Map.get(suggestion, "breadcrumb", "")}
                    </div>
                    <!-- Title -->
                    <div class="text-sm font-medium text-gray-900 group-hover:text-green-700 mb-1">
                      {Map.get(suggestion, "title", "")}
                    </div>
                    <!-- Description -->
                    <div class="text-xs text-gray-600 line-clamp-2">
                      {Map.get(suggestion, "description", "")}
                    </div>
                  </div>
                  <div class="flex items-center gap-1 text-xs text-gray-500 flex-shrink-0">
                    <span class="bg-gray-100 text-gray-700 px-2 py-1 rounded-full">
                      {Float.round(Map.get(suggestion, "relevance_score", 0), 2)}
                    </span>
                  </div>
                </div>
              </button>
            </div>
          </div>
          <button
            type="submit"
            disabled={@keyword_loading}
            class="bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white font-medium py-3 px-6 rounded-lg transition-colors"
          >
            {if @keyword_loading, do: "Searching...", else: "Search"}
          </button>
          <button
            :if={@keyword_query != ""}
            type="button"
            phx-click="clear_keyword"
            class="bg-gray-500 hover:bg-gray-600 text-white font-medium py-3 px-4 rounded-lg transition-colors"
          >
            Clear
          </button>
        </div>
      </form>
      
    <!-- Backdrop for blur effect -->
      <div
        :if={@show_autocomplete}
        class="fixed inset-0 bg-black bg-opacity-10 z-40"
        phx-click="hide_autocomplete"
      >
      </div>
    </div>
    """
  end

  @doc """
  Renders keyword search results
  """
  attr :results, :map, required: true

  def keyword_results_display(assigns) do
    ~H"""
    <div class="mt-6 space-y-4">
      <div class="border rounded-lg p-6 bg-white shadow-sm">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">Search Results</h3>
          <span class="text-xs bg-green-100 text-green-800 px-2 py-1 rounded-full font-medium">
            {length(Map.get(@results, "results", []))} results
          </span>
        </div>

        <div :if={Map.get(@results, "results", []) == []} class="text-center py-8">
          <p class="text-gray-500">No results found. Try different keywords.</p>
        </div>

        <div :if={Map.get(@results, "results", []) != []} class="space-y-4">
          <.keyword_result_item :for={result <- Map.get(@results, "results", [])} result={result} />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single keyword search result item
  """
  attr :result, :map, required: true

  def keyword_result_item(assigns) do
    ~H"""
    <div class="border border-gray-200 rounded-lg p-5 hover:border-green-300 hover:bg-green-50 transition-colors">
      <!-- Breadcrumb -->
      <div class="text-xs text-gray-500 mb-2">
        {Map.get(@result, "breadcrumb", "")}
      </div>
      
    <!-- Title as clickable link -->
      <a
        href={Map.get(@result, "academy_url", "")}
        target="_blank"
        rel="noopener noreferrer"
        class="block group"
      >
        <h4 class="text-lg font-medium text-blue-600 group-hover:text-blue-800 group-hover:underline mb-2">
          {Map.get(@result, "title", "")}
        </h4>
      </a>
      
    <!-- Description -->
      <p class="text-sm text-gray-600 mb-3 leading-relaxed">
        {Map.get(@result, "description", "")}
      </p>
      
    <!-- Meta information -->
      <div class="flex items-center justify-between text-xs text-gray-500">
        <div class="flex items-center gap-4">
          <span class="bg-gray-100 text-gray-700 px-2 py-1 rounded-full">
            Category: {Map.get(@result, "category", "")}
          </span>
          <span class="bg-green-100 text-green-700 px-2 py-1 rounded-full">
            Score: {Float.round(Map.get(@result, "relevance_score", 0), 2)}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span :if={Map.get(@result, "author", "") != ""}>
            by {Map.get(@result, "author", "")}
          </span>
          <span :if={Map.get(@result, "last_modified", "") != ""}>
            • {format_date(Map.get(@result, "last_modified", ""))}
          </span>
        </div>
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
            confidence_class(@answer_data.confidence)
          ]}>
            {String.upcase(@answer_data.confidence || "unknown")} CONFIDENCE
          </span>
          <span class="text-xs text-gray-500">
            {format_time(@answer_data.total_time_ms)}
          </span>
        </div>
      </div>

      <div class="prose prose-sm max-w-none text-gray-800
                  prose-headings:text-gray-900 prose-headings:font-semibold prose-headings:mb-4 prose-headings:mt-6
                  prose-h1:text-xl prose-h2:text-lg prose-h3:text-base
                  prose-p:mb-4 prose-p:leading-relaxed
                  prose-strong:text-gray-900 prose-strong:font-semibold
                  prose-a:text-blue-600 prose-a:no-underline hover:prose-a:underline
                  prose-ol:list-decimal prose-ul:list-disc prose-li:my-1
                  prose-code:bg-gray-100 prose-code:text-gray-900 prose-code:px-2 prose-code:py-1 prose-code:rounded prose-code:text-sm prose-code:font-mono
                  prose-pre:bg-gray-900 prose-pre:text-gray-100 prose-pre:p-4 prose-pre:rounded-lg prose-pre:overflow-x-auto prose-pre:text-sm prose-pre:font-mono
                  prose-blockquote:border-l-4 prose-blockquote:border-blue-500 prose-blockquote:pl-4 prose-blockquote:italic">
        {raw(markdown_to_html(@answer_data.answer))}
      </div>
    </div>
    """
  end

  @doc """
  Renders feedback buttons for assistant responses
  """
  attr :message_id, :string, required: true
  attr :current_feedback, :string, default: nil

  def feedback_buttons(assigns) do
    ~H"""
    <div class="flex items-center gap-3 mt-4 pt-4 border-t border-gray-200">
      <span class="text-sm text-gray-600">Was this helpful?</span>

      <button
        phx-click="submit_feedback"
        phx-value-message_id={@message_id}
        phx-value-feedback_type="thumbs_up"
        class={[
          "flex items-center gap-1 px-3 py-1 rounded-lg text-sm font-medium transition-colors",
          if(@current_feedback == "thumbs_up",
            do: "bg-green-100 text-green-800 border border-green-300",
            else:
              "bg-gray-100 text-gray-700 hover:bg-green-50 hover:text-green-700 border border-gray-300"
          )
        ]}
      >
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
          <path d="M2 10.5a1.5 1.5 0 113 0v6a1.5 1.5 0 01-3 0v-6zM6 10.333v5.43a2 2 0 001.106 1.79l.05.025A4 4 0 008.943 18h5.416a2 2 0 001.962-1.608l1.2-6A2 2 0 0015.56 8H12V4a2 2 0 00-2-2 1 1 0 00-1 1v.667a4 4 0 01-.8 2.4L6.8 7.933a4 4 0 00-.8 2.4z" />
        </svg>
        <span>Yes</span>
      </button>

      <button
        phx-click="submit_feedback"
        phx-value-message_id={@message_id}
        phx-value-feedback_type="thumbs_down"
        class={[
          "flex items-center gap-1 px-3 py-1 rounded-lg text-sm font-medium transition-colors",
          if(@current_feedback == "thumbs_down",
            do: "bg-red-100 text-red-800 border border-red-300",
            else:
              "bg-gray-100 text-gray-700 hover:bg-red-50 hover:text-red-700 border border-gray-300"
          )
        ]}
      >
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
          <path d="M18 9.5a1.5 1.5 0 11-3 0v-6a1.5 1.5 0 013 0v6zM14 9.667v-5.43a2 2 0 00-1.106-1.79l-.05-.025A4 4 0 0011.057 2H5.64a2 2 0 00-1.962 1.608l-1.2 6A2 2 0 004.44 12H8v4a2 2 0 002 2 1 1 0 001-1v-.667a4 4 0 01.8-2.4l1.4-1.866a4 4 0 00.8-2.4z" />
        </svg>
        <span>No</span>
      </button>
    </div>
    """
  end

  @doc """
  Renders the suggestions section with clickable suggestion links
  """
  attr :suggestions, :list, required: true
  attr :suggestions_confidence, :string, default: ""

  def suggestions_section(assigns) do
    ~H"""
    <div class="border rounded-lg bg-white shadow-sm">
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center gap-3">
          <h3 class="text-lg font-semibold text-gray-900">Related Questions</h3>
          <span
            :if={@suggestions_confidence != ""}
            class={[
              "text-xs px-2 py-1 rounded-full font-medium",
              confidence_class(@suggestions_confidence)
            ]}
          >
            {String.upcase(@suggestions_confidence)} CONFIDENCE
          </span>
        </div>
        <p class="text-sm text-gray-600 mt-1">
          Click on any question below to get an answer
        </p>
      </div>

      <div class="px-6 py-4 space-y-2">
        <button
          :for={suggestion <- @suggestions}
          phx-click="ask_suggestion"
          phx-value-suggestion={suggestion}
          class="w-full text-left p-3 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
        >
          <div class="flex items-start gap-3">
            <svg
              class="w-4 h-4 text-blue-600 mt-0.5 flex-shrink-0"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z"
                clip-rule="evenodd"
              >
              </path>
            </svg>
            <span class="text-sm text-gray-700 group-hover:text-blue-700">{suggestion}</span>
          </div>
        </button>
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
            [{Map.get(@source, "number", Map.get(@source, :number, ""))}]
          </span>
          <h4 class="font-medium text-gray-900">
            {Map.get(@source, "title", Map.get(@source, :title, ""))}
          </h4>
        </div>
        <div class="flex items-center gap-2 text-xs text-gray-500">
          <span>
            {Float.round(Map.get(@source, "similarity", Map.get(@source, :similarity, 0)) * 100, 1)}% match
          </span>
        </div>
      </div>

      <a
        href={Map.get(@source, "url", Map.get(@source, :url, ""))}
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm text-blue-600 hover:text-blue-800 hover:underline flex items-center gap-1"
      >
        <span>{Map.get(@source, "url", Map.get(@source, :url, ""))}</span>
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

  defp format_date(nil), do: ""
  defp format_date(""), do: ""

  defp format_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        datetime
        |> DateTime.to_date()
        |> Date.to_string()

      {:error, _} ->
        # Try parsing just the date part if it's in YYYY-MM-DD format
        case Date.from_iso8601(String.slice(date_string, 0..9)) do
          {:ok, date} -> Date.to_string(date)
          {:error, _} -> date_string
        end
    end
  end

  defp format_date(_), do: ""

  defp markdown_to_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _} -> html
      {:error, _html, _errors} -> markdown
      _ -> markdown
    end
  end

  defp markdown_to_html(_), do: ""
end
