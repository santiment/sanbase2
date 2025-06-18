defmodule Sanbase.AI.ChatAIService do
  @moduledoc """
  Service for generating AI responses to chat messages based on dashboard context.
  """

  require Logger

  alias Sanbase.AI.OpenAIClient
  alias Sanbase.Dashboards
  alias Sanbase.Chat

  @doc """
  Generates an AI response for a DYOR dashboard chat message.

  Takes the user message, chat context (dashboard_id, asset, metrics),
  fetches dashboard data, and generates a relevant AI response.
  """
  @spec generate_ai_response(String.t(), map(), String.t(), integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_ai_response(user_message, context, chat_id, user_id) do
    case context do
      %{"dashboard_id" => dashboard_id} when is_binary(dashboard_id) ->
        case Integer.parse(dashboard_id) do
          {dashboard_id_int, ""} ->
            do_generate_response(user_message, context, dashboard_id_int, chat_id, user_id)

          _ ->
            {:error, "Invalid dashboard_id format"}
        end

      %{"dashboard_id" => dashboard_id} when is_integer(dashboard_id) ->
        do_generate_response(user_message, context, dashboard_id, chat_id, user_id)

      _ ->
        generate_generic_response(user_message)
    end
  end

  @doc """
  Generates and updates chat title based on the first user message (async).
  """
  @spec generate_and_update_chat_title(String.t(), String.t()) :: :ok
  def generate_and_update_chat_title(chat_id, first_message) do
    Task.start(fn ->
      case openai_client().generate_chat_title(first_message) do
        {:ok, title} ->
          case Chat.update_chat_title(chat_id, title) do
            {:ok, _} -> Logger.info("Updated chat title for chat #{chat_id}")
            {:error, reason} -> Logger.error("Failed to update chat title: #{reason}")
          end

        {:error, reason} ->
          Logger.error("Failed to generate chat title: #{reason}")
      end
    end)

    :ok
  end

  @doc """
  Generates and updates chat title based on the first user message (synchronous).
  """
  @spec generate_and_update_chat_title_sync(String.t(), String.t()) ::
          {:ok, Chat.t()} | {:error, String.t()}
  def generate_and_update_chat_title_sync(chat_id, first_message) do
    case openai_client().generate_chat_title(first_message) do
      {:ok, title} ->
        case Chat.update_chat_title(chat_id, title) do
          {:ok, updated_chat} ->
            Logger.info("Updated chat title for chat #{chat_id}")
            {:ok, updated_chat}

          {:error, reason} ->
            Logger.error("Failed to update chat title: #{reason}")
            {:error, "Failed to update chat title: #{reason}"}
        end

      {:error, reason} ->
        Logger.error("Failed to generate chat title: #{reason}")
        {:error, "Failed to generate chat title: #{reason}"}
    end
  end

  defp do_generate_response(user_message, context, dashboard_id, _chat_id, user_id) do
    with {:ok, dashboard_context} <- fetch_dashboard_context(dashboard_id, user_id, context),
         {:ok, ai_response} <-
           generate_dashboard_response(user_message, context, dashboard_context) do
      {:ok, ai_response}
    else
      {:error, reason} ->
        Logger.error("Failed to generate AI response: #{reason}")
        generate_generic_response(user_message)
    end
  end

  def fetch_dashboard_context(dashboard_id, user_id, context \\ %{}) do
    case Dashboards.get_dashboard(dashboard_id, user_id) do
      {:ok, dashboard} ->
        queries_context =
          dashboard.queries
          |> Enum.map(&extract_query_info(&1, context))
          |> Enum.reject(&is_nil/1)

        context = %{
          name: dashboard.name,
          description: dashboard.description,
          queries: queries_context
        }

        {:ok, context}

      {:error, reason} ->
        {:error, "Cannot access dashboard: #{reason}"}
    end
  end

  defp extract_query_info(query, context \\ %{}) do
    # Get the asset from context or use a default
    asset = Map.get(context, "asset", "bitcoin")

    # Create a new query with the asset parameter overridden
    # That works only for DYOR dashboard because we know the key name
    query_with_params = %{
      query
      | sql_query_parameters: Map.put(query.sql_query_parameters || %{}, "Asset", asset)
    }

    case Sanbase.Queries.run_query(query_with_params, query.user, %{},
           store_execution_details: false
         ) do
      {:ok, result} ->
        %{
          name: query.name,
          description: query.description,
          sql_query_text: mask_sensitive_sql(query.sql_query_text),
          columns: result.columns,
          rows: result.rows
        }

      {:error, _} ->
        %{
          name: query.name,
          description: query.description,
          sql_query_text: mask_sensitive_sql(query.sql_query_text)
        }
    end
  end

  defp mask_sensitive_sql("<masked>"), do: "<masked>"
  defp mask_sensitive_sql(sql_text) when is_binary(sql_text), do: sql_text
  defp mask_sensitive_sql(_), do: "<unavailable>"

  defp generate_dashboard_response(user_message, context, dashboard_context) do
    system_prompt = build_dashboard_system_prompt(dashboard_context, context)

    case openai_client().chat_completion(system_prompt, user_message,
           max_tokens: 1500,
           temperature: 0.7
         ) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_dashboard_system_prompt(dashboard_context, chat_context) do
    asset = Map.get(chat_context, "asset", "cryptocurrency")
    metrics = Map.get(chat_context, "metrics", [])

    queries_info =
      dashboard_context.queries
      |> Enum.map(fn query ->
        columns_info =
          case Map.get(query, :columns) do
            nil -> "No data available"
            columns -> inspect(columns)
          end

        rows_info =
          case Map.get(query, :rows) do
            nil -> "No data available"
            rows -> inspect(rows)
          end

        """
        Query: #{query.name || "Unnamed"}
        Description: #{query.description || "No description"}
        SQL: #{query.sql_query_text}
        Columns: #{columns_info}
        Rows: #{rows_info}
        """
      end)
      |> Enum.join("\n\n")

    """
    You are an AI assistant specialized in cryptocurrency data analysis and Santiment dashboards.

    You are helping a user analyze data from the "#{dashboard_context.name}" dashboard.

    Dashboard Description: #{dashboard_context.description || "No description available"}

    Current Context:
    - Asset: #{asset}
    - Metrics: #{inspect(metrics)}

    Available Queries in Dashboard:
    #{queries_info}

    Your task is to:
    1. Answer the user's question based on the dashboard context and available queries
    2. Provide insights about the #{asset} asset when relevant
    3. Explain what the available queries can tell us about the data
    4. Suggest specific analyses or patterns to look for
    5. Keep responses focused on data analysis and actionable insights

    Be concise but informative. Focus on practical insights that help with investment research (DYOR - Do Your Own Research).
    """
  end

  defp generate_generic_response(user_message) do
    system_prompt = """
    You are an AI assistant specialized in cryptocurrency data analysis and investment research.
    Help users with their questions about cryptocurrency markets, metrics, and data analysis.
    Keep responses concise and focused on actionable insights for investment research (DYOR - Do Your Own Research).
    """

    case openai_client().chat_completion(system_prompt, user_message,
           max_tokens: 800,
           temperature: 0.7
         ) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, "Failed to generate response: #{reason}"}
    end
  end

  defp openai_client do
    Application.get_env(:sanbase, :openai_client, OpenAIClient)
  end
end
