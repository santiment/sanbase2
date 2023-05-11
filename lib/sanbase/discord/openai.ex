defmodule Sanbase.OpenAI do
  use Ecto.Schema

  require Logger

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Utils.Config
  alias Sanbase.Discord.ThreadAiContext

  @openai_url "https://api.openai.com/v1/chat/completions"

  @context_file "openai_context.txt"
  @external_resource text_file = Path.join(__DIR__, @context_file)
  @context File.read!(text_file)

  @history_steps 5

  schema "ai_context" do
    field(:answer, :string)
    field(:discord_user, :string)
    field(:question, :string)

    timestamps()
  end

  @doc false
  def changeset(openai, attrs) do
    openai
    |> cast(attrs, [:discord_user, :question, :answer])
    |> validate_required([:discord_user, :question, :answer])
  end

  def create(params) do
    changeset(%__MODULE__{}, params)
    |> Repo.insert()
  end

  def fetch_recent_history(discord_user) do
    query =
      from(c in __MODULE__,
        where: c.discord_user == ^discord_user,
        order_by: [desc: c.inserted_at],
        limit: @history_steps
      )

    Repo.all(query)
  end

  def fetch_history_context(discord_user) do
    fetch_recent_history(discord_user)
    |> Enum.reverse()
    |> Enum.map(fn history ->
      [%{role: "user", content: history.question}, %{role: "assistant", content: history.answer}]
    end)
    |> List.flatten()
  end

  def generate_sql(user_input, discord_user, args \\ []) do
    result_format =
      case Keyword.get(args, :type, :generate_sql) do
        :generate_sql -> "\nGenerate one clickhouse sql query that will:"
        :fix_error -> "\nGenerate one clickhouse sql query that will fix this error:"
      end

    current_prompt = "#{result_format} #{user_input}\n"
    history_messages = fetch_history_context(discord_user)

    example = """
    ```sql
    SELECT
    toDate32(dt) AS date,
    avg(price_usd) AS avg_price_usd,
    max(value) AS daily_active_addresses
    FROM asset_prices_v3
    JOIN daily_metrics_v2
    ON toDate32(asset_prices_v3.dt) = daily_metrics_v2.dt
    WHERE asset_prices_v3.slug = 'bitcoin'
    AND daily_metrics_v2.asset_id = get_asset_id('bitcoin')
    AND daily_metrics_v2.metric_id = get_metric_id('daily_active_addresses')
    AND toDate32(dt) < toDate32(today())
    GROUP BY date
    ORDER BY date DESC
    LIMIT 10
    ```
    """

    instructions = [
      %{
        role: "system",
        content: "You are a senior analyst with vast experience with Clickhouse database."
      },
      %{role: "user", content: "Always return sql queries between ```sql and ```"},
      %{role: "user", content: @context},
      %{
        role: "user",
        content:
          "Generate clickhouse sql query that will fetch the price in usd and daily active addresses for bitcoin for the last 10 days"
      },
      %{role: "assistant", content: example}
    ]

    messages = instructions ++ history_messages ++ [%{role: "user", content: current_prompt}]

    case generate_query(messages) do
      {:ok, completion} ->
        create(%{discord_user: discord_user, question: current_prompt, answer: completion})
        {:ok, completion}

      error ->
        error
    end
  end

  def ai(prompt, _params) do
    url = "#{metrics_hub_url()}/social_qa"

    do_request(url, prompt)
  end

  def docs(prompt, _params) do
    url = "#{metrics_hub_url()}/docs"

    do_request(url, prompt)
  end

  def do_request(url, prompt) do
    case HTTPoison.post(
           url,
           Jason.encode!(%{question: prompt}),
           [{"Content-Type", "application/json"}],
           timeout: 120_000,
           recv_timeout: 120_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        {:ok, body}

      _error ->
        {:error, "Can't fetch"}
    end
  end

  def threaded_docs(prompt, params) do
    url = "#{metrics_hub_url()}/docs"

    {msg_id, params} = Map.pop(params, :msg_id)
    context = ThreadAiContext.fetch_history_context(params, 5)

    case HTTPoison.post(
           url,
           Jason.encode!(%{question: prompt, messages: context}),
           [{"Content-Type", "application/json"}],
           timeout: 120_000,
           recv_timeout: 120_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        params = params |> Map.put(:answer, body["answer"]) |> Map.put(:question, prompt)
        {:ok, thread_db} = ThreadAiContext.create(params)
        {:ok, body, thread_db}

      error ->
        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(error)}")
        {:error, "Can't fetch", nil}
    end
  end

  def manage_pinecone_index() do
    if is_prod?() do
      url = "#{metrics_hub_url()}/manage_index"
      HTTPoison.post(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  def index(branch_name) do
    url = "#{metrics_hub_url()}/index"

    case HTTPoison.post(
           url,
           Jason.encode!(%{branch: branch_name}),
           [{"Content-Type", "application/json"}],
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        {:ok, body}

      _error ->
        {:error, "Can't fetch"}
    end
  end

  def ask(branch_name, question) do
    url = "#{metrics_hub_url()}/ask"

    case HTTPoison.post(
           url,
           Jason.encode!(%{branch: branch_name, question: question}),
           [{"Content-Type", "application/json"}],
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        {:ok, body}

      _error ->
        {:error, "Can't fetch"}
    end
  end

  def generate_query(prompt, tries \\ 1)

  def generate_query(_prompt, tries) when tries >= 5 do
    {:error, "Too many tries"}
  end

  def generate_query(prompt, tries) do
    case HTTPoison.post(@openai_url, generate_request_body(prompt), headers(),
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)

        completion =
          body["choices"] |> hd() |> get_in(["message", "content"]) |> String.trim("\n")

        {:ok, completion}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        generate_query(prompt, tries + 1)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  def insights do
    insights = fetch_last_insights(1)

    Enum.each(insights, fn insight ->
      summarize(insight)
    end)
  end

  def summarize(insight) do
    prompt = """
    Your task is to generate a short summary of this crypto insight.

    Summarize the insight below, delimited by triple
    backticks, in at most 100 words focusing on aspects such as
    the main idea, the author's opinion, and the author's conclusion.

    Insight: ```#{insight.text |> Floki.parse_document!() |> Floki.text()}```

    The result format should be:

    **Summary**: <your summary here>
    **Main idea**: <your main idea here>
    **Author's opinion**: <your opinion here>
    **Author's conclusion**: <your conclusion here>
    **Assets mentioned**: <assets mentioned here>
    **Sentiment of the article towards the assets mentioned**:  <your sentiment here>
    """

    messages = [%{role: "user", content: prompt}]

    case generate_query(messages) do
      {:ok, completion} ->
        """
        **#{insight.title}**
        By **#{insight.user.username}**, **#{NaiveDateTime.to_date(insight.published_at) |> to_string}**

        <https://insights.santiment.net/read/#{insight.id}>

        #{completion}
        """

      error ->
        error
    end
  end

  def fetch_last_insights(n \\ 3) do
    import Ecto.Query

    query =
      from(
        p in Sanbase.Insight.Post,
        where:
          p.is_deleted == false and p.is_hidden == false and p.state == "approved" and
            p.ready_state == "published",
        order_by: [desc: p.id],
        preload: [:user],
        limit: ^n
      )

    Sanbase.Repo.all(query)
  end

  defp generate_request_body(messages) do
    %{
      model: "gpt-4",
      messages: messages,
      max_tokens: 2000
    }
    |> Jason.encode!()
  end

  defp headers() do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"}
    ]
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp is_prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"
end
