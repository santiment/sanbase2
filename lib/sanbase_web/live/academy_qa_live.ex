defmodule SanbaseWeb.AcademyQALive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AcademyQAComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       # RAG (existing functionality)
       question: "",
       answer_data: nil,
       chat_id: nil,
       assistant_message_id: nil,
       assistant_feedback: nil,
       loading: false,
       error: nil,
       show_sources: false,

       # Keyword search (with autocomplete from search API)
       keyword_query: "",
       keyword_results: nil,
       keyword_loading: false,
       keyword_error: nil,
       autocomplete_suggestions: [],
       show_autocomplete: false,
       current_user: socket.assigns[:current_user]
     )}
  end

  # RAG functionality (existing)
  @impl true
  def handle_event("ask_question", %{"question" => question}, socket) do
    if String.trim(question) == "" do
      {:noreply, put_flash(socket, :error, "Please enter a question")}
    else
      send(self(), {:fetch_answer, question})

      {:noreply,
       assign(socket,
         question: question,
         loading: true,
         error: nil,
         answer_data: nil,
         assistant_message_id: nil
       )}
    end
  end

  @impl true
  def handle_event("ask_suggestion", %{"suggestion" => suggestion}, socket) do
    send(self(), {:fetch_answer, suggestion})

    {:noreply,
     assign(socket,
       question: suggestion,
       loading: true,
       error: nil,
       answer_data: nil,
       assistant_message_id: nil
     )}
  end

  # Keyword search functionality with autocomplete
  @impl true
  def handle_event("keyword_search", %{"keyword_query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, put_flash(socket, :error, "Please enter a search term")}
    else
      # If autocomplete is showing and there are suggestions, use the first one
      final_query =
        if socket.assigns.show_autocomplete and
             length(socket.assigns.autocomplete_suggestions) > 0 do
          hd(socket.assigns.autocomplete_suggestions)["title"] || query
        else
          query
        end

      send(self(), {:fetch_keyword_results, final_query})

      {:noreply,
       assign(socket,
         keyword_query: final_query,
         keyword_loading: true,
         keyword_error: nil,
         keyword_results: nil,
         show_autocomplete: false,
         autocomplete_suggestions: []
       )}
    end
  end

  @impl true
  def handle_event("keyword_input_change", %{"keyword_query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       assign(socket,
         keyword_query: query,
         autocomplete_suggestions: [],
         show_autocomplete: false
       )}
    else
      send(self(), {:fetch_autocomplete_suggestions, query})

      {:noreply,
       assign(socket,
         keyword_query: query,
         show_autocomplete: true
       )}
    end
  end

  @impl true
  def handle_event("select_autocomplete", %{"suggestion" => suggestion}, socket) do
    send(self(), {:fetch_keyword_results, suggestion})

    {:noreply,
     assign(socket,
       keyword_query: suggestion,
       keyword_loading: true,
       keyword_error: nil,
       keyword_results: nil,
       show_autocomplete: false,
       autocomplete_suggestions: []
     )}
  end

  @impl true
  def handle_event("hide_autocomplete", _params, socket) do
    {:noreply, assign(socket, show_autocomplete: false)}
  end

  # Existing functionality
  @impl true
  def handle_event("toggle_sources", _params, socket) do
    {:noreply, assign(socket, show_sources: !socket.assigns.show_sources)}
  end

  @impl true
  def handle_event("clear_question", _params, socket) do
    {:noreply,
     assign(socket,
       question: "",
       answer_data: nil,
       chat_id: nil,
       assistant_message_id: nil,
       assistant_feedback: nil,
       loading: false,
       error: nil,
       show_sources: false
     )}
  end

  @impl true
  def handle_event("clear_keyword", _params, socket) do
    {:noreply,
     assign(socket,
       keyword_query: "",
       keyword_results: nil,
       keyword_loading: false,
       keyword_error: nil,
       autocomplete_suggestions: [],
       show_autocomplete: false
     )}
  end

  @impl true
  def handle_event(
        "submit_feedback",
        %{"message_id" => message_id, "feedback_type" => feedback_type},
        socket
      ) do
    case Sanbase.Chat.update_message_feedback(message_id, feedback_type) do
      {:ok, updated_message} ->
        {:noreply, assign(socket, assistant_feedback: updated_message.feedback_type)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit feedback")}
    end
  end

  # Info handlers for async operations
  @impl true
  def handle_info({:fetch_answer, question}, socket) do
    user_id = if socket.assigns.current_user, do: socket.assigns.current_user.id, else: nil

    # Create or use existing chat
    chat_result =
      case socket.assigns.chat_id do
        nil ->
          # Create new chat for this session
          Sanbase.Chat.create_chat_with_message(user_id, question, %{}, "academy_qa")

        chat_id ->
          # Add message to existing chat
          case Sanbase.Chat.add_message_to_chat(chat_id, question, :user, %{}) do
            {:ok, _message} -> {:ok, Sanbase.Chat.get_chat_with_messages(chat_id)}
            error -> error
          end
      end

    case chat_result do
      {:ok, chat} ->
        # Generate AI response
        case Sanbase.AI.AcademyAIService.generate_standalone_response(question, user_id, true) do
          {:ok, answer_data} ->
            # Add assistant response to chat
            case Sanbase.Chat.add_assistant_response_with_sources_and_suggestions(
                   chat.id,
                   answer_data.answer,
                   answer_data.sources,
                   answer_data.suggestions || []
                 ) do
              {:ok, assistant_message} ->
                {:noreply,
                 assign(socket,
                   chat_id: chat.id,
                   assistant_message_id: assistant_message.id,
                   assistant_feedback: assistant_message.feedback_type,
                   answer_data: answer_data,
                   loading: false,
                   error: nil
                 )}

              {:error, _reason} ->
                {:noreply,
                 assign(socket,
                   loading: false,
                   error: "Failed to save response",
                   answer_data: nil,
                   assistant_message_id: nil
                 )}
            end

          {:error, error} ->
            {:noreply,
             assign(socket,
               loading: false,
               error: error,
               answer_data: nil,
               assistant_message_id: nil
             )}
        end

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           loading: false,
           error: "Failed to create chat",
           answer_data: nil,
           assistant_message_id: nil
         )}
    end
  end

  @impl true
  def handle_info({:fetch_keyword_results, query}, socket) do
    case make_academy_search_request(query) do
      {:ok, results} ->
        {:noreply,
         assign(socket,
           keyword_results: results,
           keyword_loading: false,
           keyword_error: nil
         )}

      {:error, error} ->
        {:noreply,
         assign(socket,
           keyword_loading: false,
           keyword_error: error,
           keyword_results: nil
         )}
    end
  end

  @impl true
  def handle_info({:fetch_autocomplete_suggestions, query}, socket) do
    case make_academy_search_request(query, 5) do
      {:ok, results} ->
        suggestions = Map.get(results, "results", [])
        {:noreply, assign(socket, autocomplete_suggestions: suggestions)}

      {:error, _error} ->
        {:noreply, assign(socket, autocomplete_suggestions: [])}
    end
  end

  # HTTP client functions
  defp make_academy_search_request(query, limit \\ 5) do
    url = "http://localhost:8000/academy/search"
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{query: query, limit: limit})

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status}} ->
        {:error, "Search request failed with status #{status}"}

      {:error, reason} ->
        {:error, "Search request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <div class="bg-white p-4 rounded-lg shadow">
        <div class={[
          "transition-all duration-200",
          if(@show_autocomplete, do: "opacity-30", else: "opacity-100")
        ]}>
          <.academy_header title="Academy Q&A" />
        </div>
        
    <!-- Keyword Search Section -->
        <div class="mb-6">
          <div class={[
            "transition-all duration-200",
            if(@show_autocomplete, do: "opacity-30", else: "opacity-100")
          ]}>
            <h3 class="text-lg font-semibold text-gray-900 mb-3">Keyword Search</h3>
          </div>

          <.keyword_search_form
            keyword_query={@keyword_query}
            keyword_loading={@keyword_loading}
            autocomplete_suggestions={@autocomplete_suggestions}
            show_autocomplete={@show_autocomplete}
          />

          <div class={[
            "transition-all duration-200",
            if(@show_autocomplete, do: "opacity-30 pointer-events-none", else: "opacity-100")
          ]}>
            <div :if={@keyword_error} class="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
              <p class="text-red-700 text-sm">{@keyword_error}</p>
            </div>

            <div :if={@keyword_loading} class="flex justify-center items-center h-16 mt-4">
              <p class="text-sm text-gray-500">Searching...</p>
            </div>

            <.keyword_results_display
              :if={@keyword_results && !@keyword_loading}
              results={@keyword_results}
            />
          </div>
        </div>
        
    <!-- RAG Q&A Section -->
        <div class={[
          "border-t pt-6 transition-all duration-200",
          if(@show_autocomplete, do: "opacity-30 pointer-events-none", else: "opacity-100")
        ]}>
          <h3 class="text-lg font-semibold text-gray-900 mb-3">AI Assistant (RAG)</h3>
          <.question_form question={@question} loading={@loading} />

          <div :if={@error} class="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
            <p class="text-red-700 text-sm">{@error}</p>
          </div>

          <div :if={@loading} class="flex justify-center items-center h-16 mt-4">
            <p class="text-sm text-gray-500">Getting answer...</p>
          </div>

          <div :if={@answer_data && !@loading} class="mt-6 space-y-4">
            <div>
              <.answer_display answer_data={@answer_data} />

              <.feedback_buttons
                :if={@assistant_message_id}
                message_id={@assistant_message_id}
                current_feedback={@assistant_feedback}
              />
            </div>

            <.sources_section
              sources={@answer_data.sources}
              show_sources={@show_sources}
              total_time_ms={@answer_data.total_time_ms}
            />

            <.suggestions_section
              :if={@answer_data.suggestions && length(@answer_data.suggestions) > 0}
              suggestions={@answer_data.suggestions}
              suggestions_confidence={@answer_data.suggestions_confidence}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
