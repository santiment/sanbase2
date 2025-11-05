defmodule Sanbase.AI.Embedding.BatchTest do
  @moduledoc """
  Batch testing module for OpenAI embeddings API.

  Makes multiple embedding requests with configurable delays and tracks
  success/failure statistics, including debugging headers.
  """

  require Logger

  @default_delay_ms 100
  @default_text "Test embedding request"

  @doc """
  Runs a batch of embedding requests with delays between them.

  ## Parameters
  - `count` - Number of requests to make
  - `opts` - Optional parameters:
    - `:texts` - List of texts to embed (defaults to same text repeated)
    - `:delay_ms` - Delay in milliseconds between requests (defaults to 100ms)
    - `:size` - Embedding size (optional, defaults to model default)

  ## Returns
  A map containing:
  - `:total_requests` - Total number of requests made
  - `:successful_requests` - Number of successful requests
  - `:failed_requests` - Number of failed requests
  - `:closed_errors` - Count of connection closed errors
  - `:other_errors` - List of other error types
  """
  def run_batch_test(count, opts \\ []) when is_integer(count) and count > 0 do
    texts = get_texts(count, opts)
    delay_ms = Keyword.get(opts, :delay_ms, @default_delay_ms)
    size = Keyword.get(opts, :size, nil)

    Logger.info("Starting batch embedding test: #{count} requests with #{delay_ms}ms delay")

    initial_state = %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      closed_errors: 0,
      other_errors: []
    }

    result =
      texts
      |> Enum.with_index(1)
      |> Enum.reduce(initial_state, fn {text, index}, acc ->
        Logger.info("Making request #{index}/#{count}")

        request_result = make_request_with_tracking(text, size)

        new_acc = update_statistics(acc, request_result)

        if index < count do
          Process.sleep(delay_ms)
        end

        new_acc
      end)

    log_summary(result)
    result
  end

  defp get_texts(count, opts) do
    case Keyword.get(opts, :texts) do
      nil ->
        List.duplicate(@default_text, count)

      texts when is_list(texts) ->
        if length(texts) >= count do
          Enum.take(texts, count)
        else
          texts
          |> Stream.cycle()
          |> Enum.take(count)
        end

      _ ->
        List.duplicate(@default_text, count)
    end
  end

  defp make_request_with_tracking(text, _size) do
    texts = [text]

    case Sanbase.AI.Embedding.OpenAI.make_request_with_headers(texts) do
      {:ok, %{"data" => data}, headers} ->
        embeddings = Enum.map(data, fn %{"embedding" => embedding} -> embedding end)
        debug_headers = Sanbase.AI.Embedding.OpenAI.extract_debugging_headers(headers)

        Logger.info("Request successful. Headers: #{inspect(debug_headers)}")

        {:ok, embeddings, debug_headers}

      {:error, %Req.TransportError{reason: :closed} = reason, headers} ->
        debug_headers = Sanbase.AI.Embedding.OpenAI.extract_debugging_headers(headers)

        Logger.warning("Request failed: connection closed. Headers: #{inspect(debug_headers)}")

        {:error, :closed, reason, debug_headers}

      {:error, reason, headers} ->
        debug_headers = Sanbase.AI.Embedding.OpenAI.extract_debugging_headers(headers)

        Logger.warning("Request failed: #{inspect(reason)}. Headers: #{inspect(debug_headers)}")

        {:error, :other, reason, debug_headers}
    end
  end

  defp update_statistics(state, {:ok, _embeddings, _debug_headers}) do
    %{
      state
      | total_requests: state.total_requests + 1,
        successful_requests: state.successful_requests + 1
    }
  end

  defp update_statistics(state, {:error, :closed, _reason, _debug_headers}) do
    %{
      state
      | total_requests: state.total_requests + 1,
        failed_requests: state.failed_requests + 1,
        closed_errors: state.closed_errors + 1
    }
  end

  defp update_statistics(state, {:error, :other, reason, _debug_headers}) do
    %{
      state
      | total_requests: state.total_requests + 1,
        failed_requests: state.failed_requests + 1,
        other_errors: [{state.total_requests + 1, reason} | state.other_errors]
    }
  end

  defp log_summary(result) do
    Logger.info("""
    Batch test completed:
    - Total requests: #{result.total_requests}
    - Successful: #{result.successful_requests}
    - Failed: #{result.failed_requests}
    - Connection closed errors: #{result.closed_errors}
    - Other errors: #{length(result.other_errors)}
    """)

    if result.other_errors != [] do
      Logger.warning("Other errors: #{inspect(Enum.reverse(result.other_errors))}")
    end
  end
end
