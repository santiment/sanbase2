defmodule SanbaseWeb.AcademyQALive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AcademyQAComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer_data: nil,
       chat_id: nil,
       assistant_message_id: nil,
       assistant_feedback: nil,
       loading: false,
       error: nil,
       show_sources: false,
       current_user: socket.assigns[:current_user]
     )}
  end

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
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <div class="bg-white p-4 rounded-lg shadow">
        <.academy_header title="Academy Q&A" />

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
    """
  end
end
