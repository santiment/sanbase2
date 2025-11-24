defmodule Sanbase.Stripe.SigmaQuery do
  @moduledoc """
  Module for fetching Stripe Sigma query results via the Sigma API.

  This module provides functions to:
  - List available scheduled query runs
  - Retrieve scheduled query run details
  - Download and parse CSV results
  - Preview first 10 rows of results

  ## Usage

      # List available query runs
      {:ok, query_runs} = Sanbase.Stripe.SigmaQuery.list_query_runs()

      # Fetch results from a specific query run
      {:ok, rows} = Sanbase.Stripe.SigmaQuery.fetch_query_results("sqr_123456")
  """

  require Logger

  @preview_limit 10
  @default_list_limit 100

  @doc """
  List available scheduled query runs.

  ## Parameters
  - opts: Optional keyword list with:
    - `:limit` - Number of query runs to retrieve (default: 100)

  ## Returns
  - `{:ok, query_runs}` - List of query run objects
  - `{:error, reason}` - Error from Stripe API

  ## Example
      iex> Sanbase.Stripe.SigmaQuery.list_query_runs(limit: 10)
      {:ok, [
        %{
          "id" => "sqr_123456",
          "title" => "Active Subscriptions",
          "status" => "completed",
          "created" => 1694472517,
          ...
        }
      ]}
  """
  @spec list_query_runs(keyword()) :: {:ok, list(map())} | {:error, String.t()}
  def list_query_runs(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_list_limit)
    url = "https://api.stripe.com/v1/sigma/scheduled_query_runs"
    stripe_api_key = get_stripe_api_key()

    req_opts = [
      auth: {:bearer, stripe_api_key},
      params: [limit: limit]
    ]

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"data" => query_runs}}} ->
        Logger.info("Retrieved #{length(query_runs)} scheduled query runs")
        {:ok, query_runs}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message = extract_stripe_error(body)
        Logger.error("Stripe API error listing query runs: HTTP #{status}, #{error_message}")
        {:error, "Failed to list query runs: #{error_message}"}

      {:error, reason} ->
        Logger.error("Unexpected error listing query runs: #{inspect(reason)}")
        {:error, "Failed to list query runs: #{inspect(reason)}"}
    end
  end

  @doc """
  Fetch results from a Stripe Sigma scheduled query run and return first 10 rows.

  This is the main entry point that orchestrates the entire flow:
  1. Retrieves the scheduled query run details
  2. Downloads the CSV file
  3. Parses and returns first 10 rows

  ## Parameters
  - query_run_id: The Stripe Sigma scheduled query run ID (e.g., "sqr_123456")

  ## Returns
  - `{:ok, rows}` where rows is a list of maps (max 10 items)
  - `{:error, reason}` if any step fails

  ## Example
      iex> Sanbase.Stripe.SigmaQuery.fetch_query_results("sqr_123456")
      {:ok, [
        %{"customer_email" => "user@example.com", "stripe_customer_id" => "cus_123"},
        ...
      ]}
  """
  @spec fetch_query_results(String.t()) :: {:ok, list(map())} | {:error, String.t()}
  def fetch_query_results(query_run_id) do
    Logger.info("Starting Stripe Sigma query fetch for query_run_id: #{query_run_id}")

    with {:ok, file_url} <- get_query_run_file_url(query_run_id),
         {:ok, csv_content} <- download_csv(file_url),
         {:ok, rows} <- parse_csv_preview(csv_content) do
      Logger.info("Successfully fetched #{length(rows)} rows from Stripe Sigma query")
      {:ok, rows}
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch Stripe Sigma query results: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieve a scheduled query run and extract the file URL.

  ## Parameters
  - query_run_id: The Stripe Sigma scheduled query run ID

  ## Returns
  - `{:ok, file_url}` - URL to download the CSV file
  - `{:error, reason}` - Error from Stripe API
  """
  @spec get_query_run_file_url(String.t()) :: {:ok, String.t()} | {:error, any()}
  def get_query_run_file_url(query_run_id) do
    url = "https://api.stripe.com/v1/sigma/scheduled_query_runs/#{query_run_id}"
    stripe_api_key = get_stripe_api_key()

    req_opts = [
      auth: {:bearer, stripe_api_key}
    ]

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"data" => [query_run | _]}}} ->
        handle_query_run_response(query_run, query_run_id)

      {:ok, %Req.Response{status: 200, body: %{"data" => []}}} ->
        Logger.error("Query run #{query_run_id} not found in response")
        {:error, "Query run not found"}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message = extract_stripe_error(body)
        Logger.error("Stripe API error retrieving query run: HTTP #{status}, #{error_message}")
        {:error, "Failed to retrieve query run: #{error_message}"}

      {:error, reason} ->
        Logger.error("Unexpected error retrieving query run: #{inspect(reason)}")
        {:error, "Failed to retrieve query run: #{inspect(reason)}"}
    end
  end

  defp handle_query_run_response(
         %{"status" => "completed", "file" => %{"url" => file_url}},
         query_run_id
       ) do
    Logger.info("Retrieved file URL for query run: #{query_run_id}")
    {:ok, file_url}
  end

  defp handle_query_run_response(
         %{"status" => "failed", "error" => %{"message" => error_msg}},
         query_run_id
       ) do
    Logger.error("Query run #{query_run_id} failed: #{error_msg}")
    {:error, "Query run failed: #{error_msg}"}
  end

  defp handle_query_run_response(%{"status" => "failed"}, query_run_id) do
    Logger.error("Query run #{query_run_id} failed with no error message")
    {:error, "Query run failed"}
  end

  defp handle_query_run_response(%{"status" => "canceled"}, query_run_id) do
    Logger.error("Query run #{query_run_id} was canceled")
    {:error, "Query run was canceled"}
  end

  defp handle_query_run_response(%{"status" => "timed_out"}, query_run_id) do
    Logger.error("Query run #{query_run_id} timed out")
    {:error, "Query run timed out"}
  end

  defp handle_query_run_response(%{"status" => status}, query_run_id)
       when status != "completed" do
    Logger.error("Query run #{query_run_id} is not completed, status: #{status}")
    {:error, "Query run is not completed, current status: #{status}"}
  end

  defp handle_query_run_response(query_run, query_run_id) do
    Logger.error("Query run #{query_run_id} has no file URL: #{inspect(query_run)}")
    {:error, "Query run has no file URL available"}
  end

  @doc """
  Download CSV file from Stripe file URL.

  ## Parameters
  - file_url: The URL to download the CSV from

  ## Returns
  - `{:ok, csv_content}` - Raw CSV content as string
  - `{:error, reason}` - Download error
  """
  @spec download_csv(String.t()) :: {:ok, String.t()} | {:error, any()}
  def download_csv(file_url) do
    stripe_api_key = get_stripe_api_key()

    req_opts = [
      auth: {:bearer, stripe_api_key}
    ]

    case Req.get(file_url, req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.info("Successfully downloaded CSV file (#{byte_size(body)} bytes)")
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to download CSV: HTTP #{status}, body: #{inspect(body)}")
        {:error, "Failed to download CSV: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Error downloading CSV: #{inspect(reason)}")
        {:error, "Failed to download CSV: #{inspect(reason)}"}
    end
  end

  @doc """
  Parse CSV content and return first 10 rows as list of maps.

  ## Parameters
  - csv_content: Raw CSV content as string

  ## Returns
  - `{:ok, rows}` - List of maps (max 10 items)
  - `{:error, reason}` - Parsing error
  """
  @spec parse_csv_preview(String.t()) :: {:ok, list(map())} | {:error, any()}
  def parse_csv_preview(csv_content) do
    rows =
      csv_content
      |> String.trim()
      |> NimbleCSV.RFC4180.parse_string()
      |> rows_to_maps()
      |> Enum.take(@preview_limit)

    {:ok, rows}
  rescue
    error ->
      Logger.error("Error parsing CSV: #{inspect(error)}")
      {:error, "Failed to parse CSV: #{inspect(error)}"}
  end

  defp rows_to_maps([]), do: []

  defp rows_to_maps([headers | rows]) do
    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  # Private helpers

  defp get_stripe_api_key do
    System.get_env("STRIPE_SECRET_KEY")
  end

  defp extract_stripe_error(%{"error" => %{"message" => message}}), do: message
  defp extract_stripe_error(%{"error" => error}) when is_binary(error), do: error
  defp extract_stripe_error(body), do: inspect(body)
end
