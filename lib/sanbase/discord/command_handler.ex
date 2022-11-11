defmodule Sanbase.Discord.CommandHandler do
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.Embed

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard
  alias Sanbase.Dashboard.DiscordDashboard
  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}

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
    unpin
    run-n-pin
    list
    listall
    show
  )

  def is_command?(msg) do
    String.starts_with?(msg.content, @prefix)
  end

  def handle_interaction("show_modal", interaction) do
    name_input = TextInput.text_input("Dashboard name", "dashname", placeholder: "Dashboard name")

    sql_input =
      TextInput.text_input("Execute sql query", "sqlquery",
        style: 2,
        placeholder: "SQL query",
        required: true
      )

    ar1 = ActionRow.action_row() |> ActionRow.put(name_input)
    ar2 = ActionRow.action_row() |> ActionRow.put(sql_input)

    response = %{
      type: 9,
      data: %{
        custom_id: "run_sql_modal",
        title: "Run sql query",
        min_length: 1,
        max_length: 6000,
        components: [ar1, ar2]
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  def handle_interaction("run", interaction) do
    components = interaction.data.components

    text_input_map =
      components
      |> Enum.into(%{}, fn c ->
        text_input_comp = List.first(c.components)
        {text_input_comp.custom_id, text_input_comp.value}
      end)

    args = %{
      discord_user: to_string(interaction.user.id),
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator,
      discord_message_id: to_string(interaction.id),
      pinned: false
    }

    name = text_input_map["dashname"]
    sql = text_input_map["sqlquery"]
    sql_args = []

    with {:ok, result, panel_id} <- compute_and_save(name, sql, sql_args, args) do
      table = format_table(name, result, panel_id)

      content = """
      ```sql
      #{sql}
      ```

      #{table}
      """

      ar =
        ActionRow.action_row()
        |> ActionRow.append(Button.button(label: "Pin 📌", custom_id: "pin" <> panel_id))

      response = %{
        type: 4,
        data: %{
          content: content,
          components: [ar]
        }
      }

      Nostrum.Api.create_interaction_response(interaction, response)
    end
  end

  def handle_interaction("help", interaction) do
    help_content = """
    * `/help`:
    * `/query`: Execute a SQL query
    """

    response = %{
      type: 4,
      data: %{
        content: help_content
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  def handle_interaction("pin", interaction, panel_id) do
    with {:ok, _} <- DiscordDashboard.pin(panel_id) do
      response = %{
        type: 4,
        data: %{
          content: "Query is pinned"
        }
      }

      Nostrum.Api.create_interaction_response(interaction, response)
    end
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
        "`#{@prefix} run YOUR-QUERY-NAME-HERE`\n\\`\\`\\`sql\nYOUR-SQL-QUERY-HERE\n\\`\\`\\`\n"
      )
      |> put_field("2. Pin query", "`#{@prefix} pin QUERY-ID`")
      |> put_field("3. Unpin query", "`#{@prefix} unpin QUERY-ID`")
      |> put_field(
        "4. Run query",
        "`#{@prefix} run-n-pin YOUR-QUERY-NAME-HERE`\n\\`\\`\\`sql\nYOUR-SQL-QUERY-HERE\n\\`\\`\\`\n"
      )
      |> put_field("5. List all pinned queries to this channel", "`#{@prefix} list`")
      |> put_field("6. List all globally pinned queries for the server", "`#{@prefix} listall`")
      |> put_field("7. Show the sql of query", "`#{@prefix} show QUERY-ID`")

    Api.create_message(msg.channel_id, content: "", embeds: [embed])
  end

  def exec_command("run", msg, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, false)

    args = %{
      discord_user: to_string(msg.author.id),
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      discord_user_id: to_string(msg.author.id),
      discord_user_handle: msg.author.username <> msg.author.discriminator,
      discord_message_id: to_string(msg.id),
      pinned: pinned
    }

    with {:ok, sql, sql_args} <- try_extracting_sql(msg.content),
         {:ok, name} <- try_extracting_name(msg.content),
         {:ok, result, panel_id} <- compute_and_save(name, sql, sql_args, args) do
      table = format_table(name, result, panel_id)

      ar =
        ActionRow.action_row()
        |> ActionRow.append(Button.button(label: "Pin 📌", custom_id: "pin" <> panel_id))

      Api.create_message(msg.channel_id,
        content: table,
        components: [ar],
        message_reference: %{message_id: msg.id}
      )
    else
      :sql_parse_error ->
        error_msg = """
        Malformed sql query supplied.
        Please provide the sql query in this format.
        \\`\\`\\`sql
        YOUR-SQL-QUERY-HERE
        \\`\\`\\`
        """

        Api.create_message(msg.channel_id, content: error_msg)
        exec_command("help", msg)

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
      Api.create_message(msg.channel_id,
        content: "Query `#{panel_id}` is pinned"
      )
    else
      _ ->
        Api.create_message(msg.channel_id,
          content:
            "Invalid query identificator. Query identificator looks like this: `355d2aec-dad9-4016-8312-70d7d22a9175`"
        )
    end
  end

  def exec_command("unpin", msg, opts) do
    with {:ok, panel_id} <- try_extracting_panel_id(msg.content),
         {:ok, _} <- DiscordDashboard.unpin(panel_id) do
      Api.create_message(msg.channel_id,
        content: "Query `#{panel_id}` is removed from pinned queries"
      )
    else
      _ ->
        Api.create_message(msg.channel_id,
          content:
            "Invalid query identificator. Query identificator looks like this: `355d2aec-dad9-4016-8312-70d7d22a9175`"
        )
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
      text = "Pinned queries for this channel:\n#{text}"
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
      text = "Pinned queries for this server:\n#{text}"
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
      Query #{panel.name}: `#{panel.id}`

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
      _ -> {:ok, gen_query_name()}
    end
    |> case do
      {:ok, ""} -> {:ok, gen_query_name()}
      other -> other
    end
  end

  def try_extracting_sql(content) do
    case Regex.run(~r/#{@sql_start_regex}(.*)#{@sql_end_regex}/sm, content) do
      [_, sql] -> {:ok, String.trim(sql, ";"), []}
      _ -> :sql_parse_error
    end
  end

  def format_table(name, %{rows: []}, panel_id) do
    """
    #{name}: `#{panel_id}`

    `No rows returned after query execution!`
    """
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

  def compute_and_save(name, query, query_params, args) do
    sanbase_bot_user_id = Sanbase.Repo.get_by(User, email: User.sanbase_bot_email()).id
    args = Map.put(args, :name, name)

    DiscordDashboard.create(sanbase_bot_user_id, query, args)
    |> case do
      {:ok, result, panel_id} -> {:ok, result, panel_id}
      {:error, reason} -> {:execution_error, reason}
    end
  end

  defp gen_query_name() do
    "anon_query_" <> (UUID.uuid4() |> String.split("-") |> Enum.at(0))
  end

  defp max_rows(rows, columns) do
    row_length =
      TableRex.quick_render!(rows)
      |> String.length()

    div(@max_size, row_length)
  end
end
