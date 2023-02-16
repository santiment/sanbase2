defmodule Sanbase.OpenAI do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @openai_url "https://api.openai.com/v1/completions"

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

  def fetch_previous_context(discord_user) do
    fetch_recent_history(discord_user)
    |> Enum.reverse()
    |> Enum.reduce("", fn history, acc ->
      acc <> "#{history.question}\n#{history.answer}\n"
    end)
  end

  def complete(user_input, discord_user, args \\ []) do
    result_format =
      case Keyword.get(args, :type, :generate_sql) do
        :generate_sql -> "\nGenerate one clickhouse sql query that will:"
        :fix_error -> "\nGenerate one clickhouse sql query that will fix this error:"
      end

    current_prompt = "#{result_format} #{user_input}\n"
    previous_context = fetch_previous_context(discord_user)

    prompt = """
    #{@context}
    #{previous_context}
    #{current_prompt}. If timeframe is not defined do it for last year.
    """

    case generate_query(prompt) do
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
        completion = body["choices"] |> hd() |> Map.get("text") |> String.trim("\n")
        {:ok, completion}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        generate_query(prompt, tries + 1)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp generate_request_body(prompt) do
    %{
      model: "text-davinci-003",
      prompt: prompt,
      temperature: 0.3,
      max_tokens: 400,
      top_p: 1,
      frequency_penalty: 0,
      presence_penalty: 0
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
