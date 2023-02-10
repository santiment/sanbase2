defmodule Sanbase.OpenAI do
  @openai_url "https://api.openai.com/v1/completions"

  @context_file "openai_context.txt"
  @external_resource json_file = Path.join(__DIR__, @context_file)
  @context File.read!(json_file)

  def complete(user_question) do
    result_format = "\nGenerate one clickhouse sql query that will:"
    start = ""
    prompt = "#{@context} #{result_format} #{user_question}\n\n #{start}"

    generate_query(prompt, start)
  end

  def generate_query(prompt, start) do
    case HTTPoison.post(@openai_url, generate_request_body(prompt), headers(),
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        completion = body["choices"] |> hd() |> Map.get("text") |> String.trim("\n")
        {:ok, start <> completion}

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
