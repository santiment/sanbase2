defmodule Sanbase.Insight.Categorizer do
  @moduledoc """
  Categorizes insights using LLM (gpt-5-nano) into predefined categories.
  """

  require Logger

  import Ecto.Query

  alias Sanbase.Insight.{Post, Category, PostCategory}
  alias Sanbase.Repo
  alias Sanbase.OpenAI.Question

  @base_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-5-nano"
  @receive_timeout_ms 60_000

  require Logger

  @system_prompt """
  You are an expert at categorizing crypto market insights. Your task is to analyze an insight and assign it to one or more of the following categories:

  1. On-chain market analysis: An insight that analyzes crypto markets based on network activity or wallet behavior on an asset's blockchain

  2. Social Trends market analysis: An insight that analyzes crypto markets based on discussion and discourse trends and activity across social media

  3. Education on using Santiment: An article or video that provides information and context about how to use a webpage, product, or service provided by Santiment

  4. Product launch/update: An article or video that shows off a new, revised, or updated feature that is provided by Santiment

  5. Promotional discount/sale: An article or video that announces or reminds readers about a promotion, discount, or sale for a Santiment product or service

  IMPORTANT GUIDELINES:
  - Be balanced: not too rigid (assigning only one category when multiple apply) but not too loose (assigning many categories when only one is primary)
  - If an insight is primarily in one category but slightly touches a second category, assign ONLY the primary category
  - Only assign multiple categories if the insight genuinely belongs to multiple categories with roughly equal weight
  - Return ONLY the category names as a JSON array of strings, nothing else

  Example response format: ["On-chain market analysis"]
  Or for multiple: ["On-chain market analysis", "Social Trends market analysis"]
  """

  @doc """
  Categorizes an insight using LLM.

  ## Options
  - `save: true/false` - Whether to save categories to database (default: true)
  - `force: true/false` - Whether to override existing human categories (default: false)

  ## Returns
  - `{:ok, [category_names]}` on success
  - `{:error, reason}` on failure
  """
  def categorize_insight(post_id, opts \\ []) do
    save? = Keyword.get(opts, :save, true)
    force? = Keyword.get(opts, :force, false)

    # Check if human categories exist before making API call
    if save? && PostCategory.has_human_categories?(post_id) && !force? do
      {:error, "Cannot override human-sourced categories. Use force: true to override."}
    else
      with {:ok, post} <- Post.by_id(post_id, preload?: false),
           {:ok, categories} <- call_llm_for_categorization(post) do
        if save? do
          save_categories(post_id, categories, force?)
        else
          {:ok, categories}
        end
      end
    end
  end

  @doc """
  Categorizes all published insights that don't have any categories.
  Skips insights that already have categories (human or AI).
  """
  def categorize_all_uncategorized(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(
        p in Post,
        left_join: pc in PostCategory,
        on: pc.post_id == p.id,
        where:
          p.ready_state == "published" and
            p.state == "approved" and
            is_nil(pc.id),
        limit: ^limit,
        order_by: [desc: p.published_at]
      )

    posts = Repo.all(query)
    total = length(posts)

    results =
      Enum.map(posts, fn post ->
        case categorize_insight(post.id, save: true, force: false) do
          {:ok, categories} -> {:ok, post.id, categories}
          {:error, reason} -> {:error, post.id, reason}
        end
      end)

    success_count = Enum.count(results, &match?({:ok, _, _}, &1))
    error_count = total - success_count

    Logger.info("Categorized #{success_count}/#{total} insights. Errors: #{error_count}")

    {:ok, %{total: total, success: success_count, errors: error_count, results: results}}
  end

  defp call_llm_for_categorization(%Post{} = post) do
    prompt = build_prompt(post)

    case make_openai_request(prompt) do
      {:ok, response_text} ->
        parse_categories(response_text)

      {:error, reason} ->
        Logger.error("Failed to categorize insight #{post.id}: #{inspect(reason)}")
        {:error, "LLM categorization failed: #{inspect(reason)}"}
    end
  end

  defp build_prompt(%Post{title: title, text: text}) do
    content = """
    Title: #{title || ""}

    Content:
    #{text || ""}

    Please categorize this insight. Return ONLY a JSON array of category names.
    """

    messages = [
      %{"role" => "system", "content" => @system_prompt},
      %{"role" => "user", "content" => content}
    ]

    %{
      "model" => @model,
      "messages" => messages
    }
  end

  defp make_openai_request(prompt_body) do
    api_key = Question.openai_apikey()

    case Req.post(@base_url,
           json: prompt_body,
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: @receive_timeout_ms
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, String.trim(content)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, "OpenAI API error: #{status}"}

      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_categories(response_text) do
    # Try to extract JSON array from response
    json_match = Regex.run(~r/\[.*?\]/s, response_text)

    case json_match do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, categories} when is_list(categories) ->
            # Validate category names exist
            validate_category_names(categories)

          {:ok, _} ->
            {:error, "LLM returned invalid format: expected array"}

          {:error, _} ->
            {:error, "Could not parse LLM response as JSON"}
        end

      _ ->
        # Try parsing the whole response as JSON
        case Jason.decode(response_text) do
          {:ok, categories} when is_list(categories) ->
            validate_category_names(categories)

          _ ->
            {:error, "Could not parse LLM response as JSON"}
        end
    end
  end

  defp validate_category_names(category_names) do
    # Get all valid category names from database
    valid_names =
      Category.all()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    # Filter to only valid categories
    valid_categories =
      category_names
      |> Enum.filter(&MapSet.member?(valid_names, &1))
      |> Enum.uniq()

    if Enum.empty?(valid_categories) do
      {:error, "No valid categories found in LLM response: #{inspect(category_names)}"}
    else
      {:ok, valid_categories}
    end
  end

  defp save_categories(post_id, category_names, force?) do
    # Check if human categories exist
    if PostCategory.has_human_categories?(post_id) && !force? do
      {:error, "Cannot override human-sourced categories. Use force: true to override."}
    else
      # Get category IDs from names
      categories = Category.by_names(category_names)

      if length(categories) != length(category_names) do
        {:error, "Some category names not found: #{inspect(category_names)}"}
      else
        category_ids = Enum.map(categories, & &1.id)

        if force? do
          # When forcing, delete ALL existing categories (both AI and human)
          # then assign new AI-sourced categories
          PostCategory.delete_all_categories(post_id)
          PostCategory.assign_categories(post_id, category_ids, "ai")
        else
          # Delete only AI categories, then assign new ones
          PostCategory.delete_ai_categories(post_id)
          PostCategory.assign_categories(post_id, category_ids, "ai")
        end

        {:ok, category_names}
      end
    end
  end
end
