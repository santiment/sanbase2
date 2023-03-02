defmodule Sanbase.OpenAI do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

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
      %{role: "user", content: "Always retrun sql queries between ```sql and ```"},
      %{role: "user", content: @context},
      %{
        role: "user",
        content:
          "Generate clickhouse sql query that will fetch the price in usd and daily active addresses for bitcoin for the last 10 days"
      },
      %{role: "assistant", content: example}
    ]

    messages = history_messages ++ instructions ++ [%{role: "user", content: current_prompt}]

    case generate_query(messages) do
      {:ok, completion} ->
        create(%{discord_user: discord_user, question: current_prompt, answer: completion})
        {:ok, completion}

      error ->
        error
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

  defp generate_request_body(messages) do
    %{
      model: "gpt-3.5-turbo",
      messages: messages,
      max_tokens: 400
    }
    |> Jason.encode!()
  end

  defp headers() do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"}
    ]
  end
end
