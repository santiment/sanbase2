defmodule Sanbase.OpenAI do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @openai_url "https://api.openai.com/v1/completions"

  @context_file "openai_context.txt"
  @external_resource text_file = Path.join(__DIR__, @context_file)
  @context File.read!(text_file)
  @history_steps 3

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

  def fetch_recent_history do
    query =
      from(c in __MODULE__,
        where: c.discord_user == ^discord_user,
        order_by: [desc: c.inserted_at],
        limit: @history_steps
      )

    Repo.all(query)
  end

  def fetch_previous_context() do
    fetch_recent_history
    |> Enum.reverse()
    |> Enum.reduce("", fn history, acc ->
      acc = acc <> "Q: #{history.question}\nA: #{history.answer}\n"
    end)
  end

  def complete(discord_user, user_question) do
    result_format = "\nGenerate one clickhouse sql query that will:"
    current_prompt = "#{result_format} #{user_question}\n"
    previous_context = fetch_previous_context()
    prompt = "#{@context} #{previous_context} #{current_prompt}"

    case generate_query(prompt) do
      {:ok, completion} ->
        create(%{discord_user: discord_user, question: current_prompt, answer: completion})

        {:ok, completion}

      error ->
        error
    end
  end

  def generate_query(prompt) do
    case HTTPoison.post(@openai_url, generate_request_body(prompt), headers(),
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        completion = body["choices"] |> hd() |> Map.get("text") |> String.trim("\n")
        {:ok, completion}

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
