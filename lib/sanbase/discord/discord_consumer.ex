defmodule Sanbase.Nostrum do
  def init() do
    Application.put_env(:nostrum, :token, System.get_env("DISCORD_BOT_QUERY_TOKEN"))
  end

  def enabled?() do
    Application.get_env(:nostrum, :token) != nil
  end
end

defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Sanbase.Dashboard

  alias Nostrum.Struct.Embed

  @prefix "!qb"
  @commands ~w(help run save chart)

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case is_command?(msg) do
      true -> handle_command(msg)
      _ -> :ignore
    end
  end

  def is_command?(msg) do
    String.starts_with?(msg.content, @prefix)
  end

  def handle_command(msg) do
    with {:ok, command} <- extract_command(msg.content) do
      run_command(command, msg)
    else
      {:error, :invalid_command} ->
        run_command(:invalid_command, msg)
        run_command("help", msg)
    end
  end

  def extract_command(content) do
    case Regex.run(~r/#{@prefix}\s+(\w+)/, content) do
      [_, command] when command in @commands -> {:ok, command}
      _ -> {:error, :invalid_command}
    end
  end

  def run_command("run", msg) do
    with {:ok, sql, args} <- try_extracting_sql(msg.content),
         {:ok, result} <- compute(sql, args) do
      table = format_table(result)
      Api.create_message(msg.channel_id, content: table)
    else
      {:execution_error, reason} ->
        content = """
        ```
        #{String.slice(reason, 0, 500)}
        ```
        """

        Api.create_message(msg.channel_id, content: content)
    end
  end

  def run_command("help", msg) do
    help_content = "Usage: to be done"
    Api.create_message(msg.channel_id, content: help_content)
  end

  def run_command(:invalid_command, msg) do
    Api.create_message(msg.channel_id, content: "Invalid command entered")
  end

  def try_extracting_sql(msg) do
    case Regex.run(~r/```sql(.*)```/sm, msg) do
      [_, sql] -> {:ok, sql, []}
      _ -> :error
    end
  end

  def format_table(response) do
    rows = response.rows |> Enum.take(5)
    table = TableRex.quick_render!(rows, response.columns)

    """
    query_id: `#{response.san_query_id}`

    ```
    #{table}
    ```
    """
  end

  def create_test_embed do
    chart = "https://preview-stage.santiment.net/chart/VoelQMj2"

    embed =
      %Embed{}
      |> put_title("Test embed")
      |> put_description("Bitcoin's price")
      |> put_url(chart)
      |> put_image(chart)
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(event) do
    :noop
  end

  def compute(query, params) do
    san_query_id = UUID.uuid4()

    Dashboard.Query.run(query, params, san_query_id, 31)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:execution_error, reason}
    end
  end
end
