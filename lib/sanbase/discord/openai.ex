defmodule Sanbase.OpenAI do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @openai_url "https://api.openai.com/v1/completions"

  @context_file "openai_context.txt"
  @slugs_file "slugs.csv"
  @metrics_file "metrics.csv"
  @metrics2_file "metrics2.csv"
  @metrics3_file "metrics3.csv"

  @external_resource text_file = Path.join(__DIR__, @context_file)
  @external_resource slugs_file = Path.join(__DIR__, @slugs_file)
  @external_resource metrics_file = Path.join(__DIR__, @metrics_file)
  @external_resource metrics2_file = Path.join(__DIR__, @metrics2_file)
  @external_resource metrics3_file = Path.join(__DIR__, @metrics3_file)

  @context File.read!(text_file)
  @slugs_context File.read!(slugs_file)
  @metrics_context File.read!(metrics_file)
  @metrics2_context File.read!(metrics2_file)
  @metrics3_context File.read!(metrics3_file)

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
      acc = acc <> "#{history.question}\n#{history.answer}\n"
    end)
  end

  def translate(user_input, discord_user) do
    result_format = "return a line in format metric,slug,table based on this input:"
    prompt = "#{@slugs_context}\n#{@metrics2_context}\n#{result_format} #{user_input}"
    IO.puts(prompt)
    {:ok, result} = generate_query(prompt) |> IO.inspect()

    complete(user_input, discord_user, translation: "\nUsing: \nmetric,slug,table\n#{result}\n")
  end

  def complete(user_input, discord_user, args \\ []) do
    result_format =
      case Keyword.get(args, :type, :generate_sql) do
        :generate_sql -> "\nGenerate one clickhouse sql query that will:"
        :fix_error -> "\nGenerate one clickhouse sql query that will fix this error:"
      end

    translation = Keyword.get(args, :translation, "")
    result_format = "\nGenerate one clickhouse sql query that will:"
    current_prompt = "#{translation} #{result_format} #{user_input}\n"
    previous_context = fetch_previous_context(discord_user)
    prompt = "#{@context} #{previous_context} #{current_prompt}"
    IO.puts(prompt)

    case generate_query(prompt) do
      {:ok, completion} ->
        create(%{discord_user: discord_user, question: current_prompt, answer: completion})
        IO.puts(completion)
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
