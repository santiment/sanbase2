defmodule Sanbase.Discord.CommandHandler do
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.Embed

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard
  alias Sanbase.Dashboard.DiscordDashboard

  @prefix "!q"
  @cmd_regex "[\\w-]+"
  @panel_id_regex "[a-z0-9-]*"
  @sql_start_regex "```sql"
  @sql_end_regex "```"

  @max_size 1800

  @commands ~w(
    help
    run
    pin
    run-n-pin
    list
    listall
    show
  )

  def is_command?(msg) do
    String.starts_with?(msg.content, @prefix)
  end

  def handle_command(msg) do
    with {:ok, command} <- try_extracting_command(msg.content) do
      exec_command(command, msg)
    else
      {:error, :invalid_command} ->
        exec_command(:invalid_command, msg)
        exec_command("help", msg)
    end
  end

  def exec_command("help", msg) do
    embed =
      %Embed{}
      |> put_title("Help")
      |> put_description("Commands usage:\n")
      |> put_field(
        "1. Run query",
        "#{@prefix} run YOUR-QUERY-NAME-HERE\n\\`\\`\\`sql\nYOUR-SQL-QUERY-HERE\n\\`\\`\\`\n"
      )
      |> put_field("2. Pin query", "`#{@prefix} pin QUERY-ID`")
      |> put_field(
        "3. Run query",
        "#{@prefix} run-n-pin YOUR-QUERY-NAME-HERE\n\\`\\`\\`sql\nYOUR-SQL-QUERY-HERE\n\\`\\`\\`\n"
      )
      |> put_field("4. List all pinned queries to this channel", "`#{@prefix} list`")
      |> put_field("5. List all globally pinned queries for the server", "#{@prefix} listall")
      |> put_field("6. Show the sql of query", "`#{@prefix} show QUERY-ID`")

    Api.create_message(msg.channel_id, content: "", embeds: [embed])
  end

  def exec_command("run", msg, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, false)

    with {:ok, name} <- try_extracting_name(msg.content),
         {:ok, sql, args} <- try_extracting_sql(msg.content),
         {:ok, result, panel_id} <- compute_and_save(name, sql, args, msg, pinned: pinned) do
      table = format_table(name, result, panel_id)
      Api.create_message(msg.channel_id, content: table)
    else
      {:execution_error, reason} ->
        content = """
        ```
        #{String.slice(reason, 0, 1500)}
        ```
        """

        Api.create_message(msg.channel_id, content: content)
    end
  end

  def exec_command("pin", msg, opts) do
    with {:ok, panel_id} <- try_extracting_panel_id(msg.content),
         {:ok, _} <- DiscordDashboard.pin(panel_id) do
      Api.create_message(msg.channel_id, content: "#{panel_id} is pinned")
    else
      _ -> Api.create_message(msg.channel_id, content: "Invalid query identificator")
    end
  end

  def exec_command("run-n-pin", msg, opts) do
    exec_command("run", msg, pinned: true)
  end

  def exec_command("list", msg, opts) do
    with pinned when is_list(pinned) and pinned != [] <-
           DiscordDashboard.list_pinned_channel(
             to_string(msg.channel_id),
             to_string(msg.guild_id)
           ) do
      text = Enum.map(pinned, fn p -> "#{p.name}: `#{p.panel_id}`" end) |> Enum.join("\n")
      Api.create_message(msg.channel_id, content: text)
    else
      _ ->
        Api.create_message(msg.channel_id,
          content: "There are no pinned queries for this channel."
        )
    end
  end

  def exec_command("listall", msg, opts) do
    with pinned when is_list(pinned) and pinned != [] <-
           DiscordDashboard.list_pinned_global(to_string(msg.guild_id)) do
      text = Enum.map(pinned, fn p -> "#{p.name}: `#{p.panel_id}`" end) |> Enum.join("\n")
      Api.create_message(msg.channel_id, content: text)
    else
      _ ->
        Api.create_message(msg.channel_id, content: "There are no pinned queries for this server")
    end
  end

  def exec_command("show", msg, opts) do
    with {:ok, panel_id} <- try_extracting_panel_id(msg.content),
         %DiscordDashboard{} = dd <- DiscordDashboard.by_panel_id(panel_id) do
      panel = List.first(dd.dashboard.panels)

      content = """
      #{panel.name}: `#{panel.id}`
      ```sql

      #{panel.sql["query"]}
      ```
      """

      Api.create_message(msg.channel_id, content: content)
    else
      _ ->
        Api.create_message(msg.channel_id, content: "There is no query with this identificator")
    end
  end

  def exec_command(:invalid_command, msg, opts) do
    Api.create_message(msg.channel_id, content: "Invalid command entered")
  end

  def try_extracting_command(content) do
    case Regex.run(~r/#{@prefix}\s+(#{@cmd_regex})/, content) do
      [_, command] when command in @commands -> {:ok, command}
      _ -> {:error, :invalid_command}
    end
  end

  def try_extracting_panel_id(content) do
    case Regex.run(~r/#{@prefix}\s+#{@cmd_regex}\s+(#{@panel_id_regex})/sm, content) do
      [_, panel_id] -> {:ok, String.trim(panel_id)}
      _ -> :error
    end
  end

  def try_extracting_name(content) do
    case Regex.run(~r/#{@prefix}\s+#{@cmd_regex}\s+(.*)#{@sql_start_regex}/sm, content) do
      [_, name] -> {:ok, String.trim(name)}
      _ -> :error
    end
  end

  def try_extracting_sql(content) do
    case Regex.run(~r/#{@sql_start_regex}(.*)#{@sql_end_regex}/sm, content) do
      [_, sql] -> {:ok, sql, []}
      _ -> :error
    end
  end

  def format_table(name, response, panel_id) do
    max_rows = response.rows |> Enum.take(1) |> max_rows(response.columns)
    rows = response.rows |> Enum.take(max_rows - 1)
    table = TableRex.quick_render!(rows, response.columns)

    String.length(table)

    """
    #{name}: `#{panel_id}`

    ```
    #{table}
    ```
    """
  end

  def compute_and_save(name, query, params, msg, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, false)
    sanbase_bot_user_id = Sanbase.Repo.get_by(User, email: User.sanbase_bot_email()).id

    DiscordDashboard.create(sanbase_bot_user_id, query, %{
      name: name,
      discord_user: to_string(msg.author.id),
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      pinned: pinned
    })
    |> case do
      {:ok, result, panel_id} -> {:ok, result, panel_id}
      {:error, reason} -> {:execution_error, reason}
    end
  end

  defp max_rows(rows, columns) do
    row_length =
      TableRex.quick_render!(rows)
      |> String.length()

    div(@max_size, row_length)
  end
end
