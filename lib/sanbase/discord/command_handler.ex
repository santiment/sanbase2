defmodule Sanbase.Discord.CommandHandler do
  import Nostrum.Struct.Embed
  import Ecto.Query

  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard.DiscordDashboard
  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}
  alias Sanbase.Utils.Config

  @prefix "!q "
  @ai_prefix "!ai "
  @docs_prefix "!docs "
  @index_prefixes ["!gi ", "!git_index "]
  @ask_prefixes ["!ga ", "!git_ask "]
  @mock_role_id 1
  @max_size 1800
  @ephemeral_message_flags 64

  def is_command?(content) do
    String.starts_with?(content, @prefix)
  end

  def is_ai_command?(content) do
    String.starts_with?(content, @ai_prefix)
  end

  def is_docs_command?(content) do
    String.starts_with?(content, @docs_prefix)
  end

  def is_index_command?(content) do
    String.starts_with?(content, @index_prefixes)
  end

  def is_ask_command?(content) do
    String.starts_with?(content, @ask_prefixes)
  end

  def handle_interaction("query", interaction) do
    name_input = TextInput.text_input("Dashboard name", "dashname", placeholder: "Dashboard name")

    sql_input =
      TextInput.text_input("Run query", "sqlquery",
        style: 2,
        placeholder: "SQL query",
        required: true
      )

    ar1 = ActionRow.action_row() |> ActionRow.put(name_input)
    ar2 = ActionRow.action_row() |> ActionRow.put(sql_input)

    response = %{
      type: 9,
      data: %{
        custom_id: "run",
        title: "Run sql query",
        min_length: 1,
        max_length: 4000,
        components: [ar1, ar2]
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  def handle_interaction("chart", interaction) do
    interaction_ack_visible(interaction)

    focused_option =
      interaction.data.options
      |> Enum.filter(& &1.focused)
      |> List.first()

    options_map =
      interaction.data.options |> Enum.into(%{}, fn option -> {option.name, option.value} end)

    if focused_option do
      case focused_option.name do
        "project" ->
          autocomplete_projects(interaction, focused_option.value)

        "metric" ->
          autocomplete_metrics(interaction, focused_option.value, options_map["project"])
      end
    else
      files = fetch_chart_files(options_map["metric"], options_map["project"])

      if files != [] do
        Nostrum.Api.edit_interaction_response(interaction, %{
          content: "",
          files: files
        })
      else
        content = "Can't create chart for #{options_map["project"]}'s #{options_map["metric"]}"
        edit_interaction_response(interaction, content, [], [])
      end
    end
  end

  def handle_interaction("run", interaction) do
    interaction_ack_visible(interaction)

    {name, sql} = parse_modal_component(interaction)
    args = get_additional_info(interaction)

    with {:ok, exec_result, dashboard, panel_id} <- compute_and_save(name, sql, [], args) do
      components = [action_row(panel_id)]
      embeds = create_chart_embed(exec_result, dashboard, panel_id)

      edit_response_with_data(exec_result, interaction, %{
        embeds: embeds,
        components: components,
        name: name
      })
    else
      {:execution_error, reason} ->
        content = sql_execution_error(reason, interaction.user.id, name)
        edit_interaction_response(interaction, content)
    end
  end

  def handle_interaction("list", interaction) do
    with pinned when is_list(pinned) and pinned != [] <-
           DiscordDashboard.list_pinned_channel(
             to_string(interaction.channel_id),
             to_string(interaction.guild_id)
           ) do
      Nostrum.Api.create_interaction_response(
        interaction,
        interaction_message_response("List of pinned queries")
      )

      pinned
      |> Enum.with_index()
      |> Enum.each(fn {dd, idx} ->
        text = "#{idx + 1}. #{dd.name}"

        Api.create_message(interaction.channel_id,
          content: text,
          components: [action_row(dd.panel_id, dd)]
        )
      end)
    else
      _ ->
        interaction_msg(interaction, "There are no pinned queries for this channel.")
    end
  end

  def handle_interaction("help", interaction) do
    embed =
      %Embed{}
      |> put_title("Help")
      |> put_description("Available commands:\n")
      |> put_field("/query", "Execute a SQL query over Santiment's datasets")
      |> put_field("/list", "List all pinned queries for the current channel")
      |> put_field("/help", "Show help info and commands")

    data = %{
      type: 4,
      data: %{
        content: "",
        embeds: [embed],
        flags: @ephemeral_message_flags
      }
    }

    Nostrum.Api.create_interaction_response(interaction, data)
  end

  def handle_interaction("auth", interaction) do
    Nostrum.Api.create_interaction_response(
      interaction,
      interaction_message_response("Sent you a DM with instructions")
    )

    {:ok, channel} = Api.create_dm(interaction.user.id)

    Api.create_message(channel.id, content: "Test bot DMs")
  end

  def handle_interaction("create-admin", interaction) do
    options_map = Enum.into(interaction.data.options, %{}, fn o -> {o.name, o.value} end)

    Api.add_guild_member_role(
      interaction.guild_id,
      options_map["user"],
      @mock_role_id
    )

    Nostrum.Api.create_interaction_response(
      interaction,
      interaction_message_response("New admin created")
    )
  end

  def handle_interaction("remove-admin", interaction) do
    options_map = Enum.into(interaction.data.options, %{}, fn o -> {o.name, o.value} end)

    Api.remove_guild_member_role(
      interaction.guild_id,
      options_map["user"],
      @mock_role_id
    )

    Nostrum.Api.create_interaction_response(
      interaction,
      interaction_message_response("Admin removed")
    )
  end

  def handle_interaction("rerun", interaction, panel_id) do
    interaction_ack(interaction)
    args = get_additional_info(interaction)

    with {:ok, exec_result, dashboard, _dashboard_id} <-
           DiscordDashboard.execute(sanbase_bot_id(), panel_id, args) do
      panel = List.first(dashboard.panels)
      components = [action_row(panel_id)]
      embeds = create_chart_embed(exec_result, dashboard, panel_id)

      edit_response_with_data(exec_result, interaction, %{
        embeds: embeds,
        components: components,
        name: panel.name
      })
    else
      {:execution_error, reason} ->
        content =
          sql_execution_error(
            reason,
            interaction.user.id,
            DiscordDashboard.by_panel_id(panel_id).name
          )

        edit_interaction_response(interaction, content)
    end
  end

  def handle_interaction("pin", interaction, panel_id) do
    with true <- can_manage_channel?(interaction),
         {:ok, dd} <- DiscordDashboard.pin(panel_id) do
      interaction_msg(interaction, "<@#{interaction.user.id}> pinned #{dd.name}")
    end
    |> handle_pin_unpin_error("pin", interaction)
  end

  def handle_interaction("unpin", interaction, panel_id) do
    with true <- can_manage_channel?(interaction),
         {:ok, dd} <- DiscordDashboard.unpin(panel_id) do
      interaction_msg(interaction, "<@#{interaction.user.id}> unpinned #{dd.name}")
    end
    |> handle_pin_unpin_error("unpin", interaction)
  end

  def handle_interaction("show", interaction, panel_id) do
    with %DiscordDashboard{} = dd <- DiscordDashboard.by_panel_id(panel_id) do
      panel = List.first(dd.dashboard.panels)

      content = """
      #{panel.name}
      ```sql

      #{panel.sql["query"]}
      ```
      """

      interaction_msg(interaction, content, %{flags: @ephemeral_message_flags})
    else
      _ ->
        interaction_msg(interaction, "Query is removed from our database", %{
          flags: @ephemeral_message_flags
        })
    end
  end

  def handle_command("run", name, sql, msg) do
    {:ok, loading_msg} =
      Api.create_message(
        msg.channel_id,
        content: "Your query is running ...",
        message_reference: %{message_id: msg.id}
      )

    args = get_additional_info_msg(msg)

    with {:ok, exec_result, dd, panel_id} <- compute_and_save(name, sql, [], args) do
      components = [action_row(panel_id)]
      embeds = create_chart_embed(exec_result, dd, panel_id)

      edit_response_with_data(exec_result, msg, %{
        old_msg_id: loading_msg.id,
        embeds: embeds,
        components: components,
        name: name
      })
    else
      {:execution_error, reason} ->
        content = sql_execution_error(reason, msg.author.id, name)
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
  end

  def handle_command("ai", msg) do
    {:ok, loading_msg} =
      Api.create_message(
        msg.channel_id,
        content: ":robot: Thinking...",
        message_reference: %{message_id: msg.id}
      )

    prompt = String.trim(msg.content, "!ai")

    case Sanbase.OpenAI.generate_sql(
           prompt,
           msg.author.username <> msg.author.discriminator
         ) do
      {:ok, response} ->
        content = """
        #{response}
        """

        components =
          case Regex.run(~r/```(?:sql)?([^`]*)```/ms, content) do
            [_, _] -> [ai_action_row()]
            nil -> []
          end

        Api.edit_message(msg.channel_id, loading_msg.id,
          content: content,
          components: components
        )

      {:error, _} ->
        content = "Couldn't generate sql query based on your prompt"
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
  end

  def handle_command("docs", msg) do
    {:ok, loading_msg} =
      Api.create_message(
        msg.channel_id,
        content: ":robot: Thinking...",
        message_reference: %{message_id: msg.id}
      )

    prompt = String.trim(msg.content, "!docs")

    case Sanbase.OpenAI.docs(
           prompt,
           msg.author.username <> msg.author.discriminator
         ) do
      {:ok, response} ->
        content = """
        #{response["answer"]}
        #{response["sources"] |> String.replace("../academy/src/docs/", " https://academy.santiment.net/") |> String.replace("index.md", "") |> String.replace("/index/", "/")}
        """

        components =
          case Regex.run(~r/```(?:sql)?([^`]*)```/ms, content) do
            [_, _] -> [ai_action_row()]
            nil -> []
          end

        Api.edit_message(msg.channel_id, loading_msg.id,
          content: content,
          components: components
        )

      {:error, _} ->
        content = "Couldn't fetch information to answer your question"
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
  end

  def handle_command("gi", msg) do
    {:ok, loading_msg} =
      Api.create_message(
        msg.channel_id,
        content: ":robot: Thinking...",
        message_reference: %{message_id: msg.id}
      )

    with {:ok, branch} <- extract_branch_name(msg.content),
         {:ok, _response} <- Sanbase.OpenAI.index(branch) do
      content = "Your git branch: #{branch} is indexed :beers:"
      Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    else
      _error ->
        content = "Couldn't index your git branch"
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
  end

  def handle_command("ga", msg) do
    {:ok, loading_msg} =
      Api.create_message(
        msg.channel_id,
        content: ":robot: Thinking...",
        message_reference: %{message_id: msg.id}
      )

    with {:ok, branch, question} <- extract_branch_name_and_question(msg.content),
         {:ok, response} <- Sanbase.OpenAI.ask(branch, question) do
      content = """
      Q: #{question}
      A: #{response["answer"]}
      Sources: #{response["sources"]}
      """

      components =
        case Regex.run(~r/```(?:sql)?([^`]*)```/ms, content) do
          [_, _] -> [ai_action_row()]
          nil -> []
        end

      Api.edit_message(msg.channel_id, loading_msg.id,
        content: content,
        components: components
      )
    else
      _error ->
        content = "Couldn't fetch answer from your git branch"
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
  end

  def handle_command("invalid_command", msg) do
    Nostrum.Api.create_message(msg.channel_id,
      content: "<:bangbang:1045078993604452465> Invalid command entered!",
      message_reference: %{message_id: msg.id}
    )
  end

  def handle_command("help", msg) do
    content = """
    Here are some valid ways to execute SQL query

    1. !q \\`select now()\\`
    2. !q test query1 \\`select now()\\`
    3. !q test query2 \\`\\`\\`
    select now()
    \\`\\`\\`
    4. !q
    \\`\\`\\`
    select now()
    \\`\\`\\`
    5. !q what's the time
    \\`\\`\\`sql
    select now()
    \\`\\`\\`
    """

    Nostrum.Api.create_message(msg.channel_id,
      content: content,
      message_reference: %{message_id: msg.id}
    )
  end

  def extract_branch_name(message) do
    case String.split(message, ~r{\s+}, parts: 2) do
      [_, branch] -> {:ok, branch}
      _ -> {:error, "Invalid input format"}
    end
  end

  def extract_branch_name_and_question(message) do
    case String.split(message, ~r{\s+}, parts: 3) do
      [_, branch, question] -> {:ok, branch, question}
      _ -> {:error, "Invalid input format"}
    end
  end

  # Example valid invocations
  #   "!q `select now()`"
  #   "!q test query1 `select now()`"
  #   "!q test query2 ```\nselect now()\n```"
  #   "!q\n```\nselect now()\n```"
  #   "!q what's the time\n```sql\nselect now()\n```"
  def parse_message_command(content) do
    regexes = [
      ~r/!q([^`]*)`([^`]+)`/,
      ~r/!q([^`]*)```sql([^`]*)```$/ms,
      ~r/!q([^`]*)```([^`]*)```$/ms
    ]

    Enum.find(regexes, &match?([_, _name, _sql], Regex.run(&1, content)))
    |> case do
      nil ->
        {:error, :invalid_command}

      regex ->
        [_, name, sql] = Regex.run(regex, content)
        name = if String.trim(name) == "", do: gen_query_name(), else: String.trim(name)
        sql = sql |> String.trim() |> String.trim(";")
        {:ok, name, sql}
    end
  end

  def header(name, discord_user) do
    """
    #{name}: <@#{discord_user}>
    """
  end

  def format_table(name, %{rows: []}, discord_user) do
    """
    #{name}: <@#{discord_user}>

    0 rows in set.
    """
  end

  def format_table(name, response, discord_user) do
    max_rows = response.rows |> Enum.take(1) |> max_rows()

    table =
      if max_rows == 0 and length(response.columns) == 1 do
        String.slice(response.rows |> hd |> hd, 0, 1900)
      else
        rows = response.rows |> Enum.take(max_rows)
        TableRex.quick_render!(rows, response.columns)
      end

    content = """
    #{name}: <@#{discord_user}>

    ```
    #{table}
    ```
    """

    if String.length(content) > 2000 do
      String.slice(content, 0, 1900) <> "\n```"
    else
      content
    end
  end

  def get_execution_summary(qe) do
    ed = qe.execution_details

    """
    ```
    #{ed["result_rows"]} rows in set. Elapsed: #{ed["query_duration_ms"] / 1000} sec.
    Processed #{Number.Human.number_to_human(ed["read_rows"])} rows, #{ed["read_gb"]} GB
    ```
    """
  end

  def compute_and_save(name, query, _query_params, args) do
    args = Map.put(args, :name, name)

    DiscordDashboard.create(sanbase_bot_id(), query, args)
    |> case do
      {:ok, result, dd, panel_id} -> {:ok, result, dd, panel_id}
      {:error, reason} -> {:execution_error, reason}
    end
  end

  # Private

  defp edit_response_with_data(
         exec_result,
         %Nostrum.Struct.Message{} = msg,
         %{old_msg_id: old_msg_id, embeds: [], components: components, name: name}
       ) do
    content = format_table(name, exec_result, to_string(msg.author.id))

    Api.edit_message(msg.channel_id, old_msg_id, content: content, components: components)
    |> maybe_add_stats?(msg, exec_result, content, components, [])
  end

  defp edit_response_with_data(
         exec_result,
         %Nostrum.Struct.Message{} = msg,
         %{old_msg_id: old_msg_id, embeds: embeds, components: components, name: name}
       ) do
    file = %{
      name: "#{name}.csv",
      body: to_csv(exec_result)
    }

    content = header(name, to_string(msg.author.id))

    Api.edit_message(msg.channel_id, old_msg_id,
      content: content,
      components: components,
      embeds: embeds,
      files: [file]
    )
  end

  defp edit_response_with_data(
         exec_result,
         %Nostrum.Struct.Interaction{} = interaction,
         %{embeds: [], components: components, name: name}
       ) do
    content = format_table(name, exec_result, to_string(interaction.user.id))

    edit_interaction_response(interaction, content, components, [])
    |> maybe_add_stats?(interaction, exec_result, content, components, [])
  end

  defp edit_response_with_data(
         exec_result,
         %Nostrum.Struct.Interaction{} = interaction,
         %{embeds: embeds, components: components, name: name}
       ) do
    file = %{
      name: "#{name}.csv",
      body: to_csv(exec_result)
    }

    content = header(name, to_string(interaction.user.id))

    Nostrum.Api.edit_interaction_response(interaction, %{
      content: content,
      components: components,
      embeds: embeds,
      files: [file]
    })
  end

  defp gen_query_name() do
    "anon_query_" <> (UUID.uuid4() |> String.split("-") |> Enum.at(0))
  end

  defp max_rows(rows) do
    row_length =
      TableRex.quick_render!(rows)
      |> String.length()

    div(@max_size, row_length)
  end

  defp interaction_ack(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{
      type: 5,
      data: %{flags: @ephemeral_message_flags}
    })
  end

  defp interaction_ack_visible(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{type: 5})
  end

  defp interaction_msg(interaction, content, opts \\ %{}) do
    Nostrum.Api.create_interaction_response(
      interaction,
      interaction_message_response(content, opts)
    )
  end

  defp interaction_message_response(content, opts \\ %{}) do
    data = %{content: content} |> Map.merge(opts)
    %{type: 4, data: data}
  end

  def edit_interaction_response(interaction, content) do
    Nostrum.Api.edit_interaction_response(interaction, %{content: content})
  end

  defp edit_interaction_response(interaction, content, components, embeds) do
    Nostrum.Api.edit_interaction_response(interaction, %{
      content: content,
      components: components,
      embeds: embeds
    })
  end

  defp parse_modal_component(interaction) do
    if interaction.message do
      content = interaction.message.content
      [_, sql] = Regex.run(~r/```(?:sql)?([^`]*)```/ms, content)
      sql = String.trim(sql)
      {gen_query_name(), sql}
    else
      components = interaction.data.components

      text_input_map =
        components
        |> Enum.into(%{}, fn c ->
          text_input_comp = List.first(c.components)
          {text_input_comp.custom_id, text_input_comp.value}
        end)

      name =
        case text_input_map["dashname"] do
          "" -> gen_query_name()
          nil -> gen_query_name()
          name -> name
        end

      sql = text_input_map["sqlquery"] |> String.trim(";")

      {name, sql}
    end
  end

  defp get_additional_info(interaction) do
    {guild_name, channel_name} = get_guild_channel(interaction.guild_id, interaction.channel_id)

    %{
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      channel_name: channel_name,
      guild_name: guild_name,
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator,
      discord_message_id: to_string(interaction.id),
      pinned: false
    }
  end

  defp get_additional_info_msg(msg) do
    {guild_name, channel_name} = get_guild_channel(msg.guild_id, msg.channel_id)

    %{
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      channel_name: channel_name,
      guild_name: guild_name,
      discord_user_id: to_string(msg.author.id),
      discord_user_handle: msg.author.username <> msg.author.discriminator,
      discord_message_id: to_string(msg.id),
      pinned: false
    }
  end

  defp maybe_add_stats?(
         prev_response,
         %Nostrum.Struct.Interaction{} = interaction,
         exec_result,
         content,
         components,
         embeds
       ) do
    Sanbase.Dashboard.QueryExecution.get_execution_stats(
      sanbase_bot_id(),
      exec_result.clickhouse_query_id
    )
    |> case do
      {:ok, qe} ->
        stats = get_execution_summary(qe)

        edit_interaction_response(interaction, content <> stats, components, embeds)

      _ ->
        prev_response
    end
  end

  defp maybe_add_stats?(
         {:ok, prev_message} = prev_response,
         %Nostrum.Struct.Message{},
         exec_result,
         content,
         components,
         embeds
       ) do
    Sanbase.Dashboard.QueryExecution.get_execution_stats(
      sanbase_bot_id(),
      exec_result.clickhouse_query_id
    )
    |> case do
      {:ok, qe} ->
        stats = get_execution_summary(qe)

        Nostrum.Api.edit_message(prev_message.channel_id, prev_message.id,
          content: content <> stats,
          components: components,
          embeds: embeds
        )

      _ ->
        prev_response
    end
  end

  defp sql_execution_error(reason, discord_user, query_name) do
    """
    <:bangbang:1045078993604452465> **Error** "#{query_name}", <@#{discord_user}>
    ```
    #{String.slice(reason, 0, @max_size)}
    ```
    """
  end

  defp action_row(panel_id, dd \\ nil) do
    dd = dd || DiscordDashboard.by_panel_id(panel_id)
    run_button = Button.button(label: "Run 🚀", custom_id: "rerun" <> "_" <> panel_id, style: 3)
    show_button = Button.button(label: "Show 📜", custom_id: "show" <> "_" <> panel_id, style: 2)

    pin_unpin_button =
      case dd.pinned do
        true -> Button.button(label: "Unpin X", custom_id: "unpin" <> "_" <> panel_id, style: 4)
        false -> Button.button(label: "Pin 📌", custom_id: "pin" <> "_" <> panel_id, style: 1)
      end

    ActionRow.action_row()
    |> ActionRow.append(run_button)
    |> ActionRow.append(show_button)
    |> ActionRow.append(pin_unpin_button)
  end

  defp ai_action_row do
    run_button = Button.button(label: "Run 🚀", custom_id: "run", style: 3)

    ActionRow.action_row()
    |> ActionRow.append(run_button)
  end

  defp create_chart_embed(exec_result, dd, panel_id) do
    dt_idx =
      Enum.find_index(exec_result.column_types, fn c ->
        c in ~w(Date DateTime Date32 DateTime64)
      end)

    if not is_nil(dt_idx) and length(exec_result.column_types) > 1 do
      data_columns =
        exec_result.columns
        |> Enum.with_index()
        |> Enum.reject(fn {_, idx} -> idx == dt_idx end)
        |> Enum.map(fn {c, _} -> c end)

      chart_type = fn column_name ->
        result = String.split(column_name, "_")

        if length(result) > 1 do
          case List.last(result) do
            "bar" -> "bar"
            "line" -> "line"
            "area" -> "area"
            "fline" -> "filledLine"
            _ -> "bar"
          end
        else
          "bar"
        end
      end

      map =
        data_columns
        |> Enum.with_index()
        |> Enum.into(%{}, fn {name, idx} -> {to_string(idx), %{node: chart_type.(name)}} end)

      settings =
        %{
          wm: data_columns,
          ws: map
        }
        |> Jason.encode!()
        |> URI.encode()

      chart =
        "https://#{img_prefix_url()}/chart/dashboard/#{dd.id}/#{panel_id}?settings=#{settings}"

      HTTPoison.get(chart)
      |> case do
        {:ok, response} ->
          if is_image?(response) do
            %Embed{}
            |> put_title(dd.name)
            |> put_url(chart)
            |> put_image(chart)
            |> List.wrap()
          else
            []
          end

        _ ->
          []
      end
    else
      []
    end
  end

  defp to_csv(exec_result) do
    NimbleCSV.RFC4180.dump_to_iodata([exec_result.columns | exec_result.rows])
  end

  defp img_prefix_url() do
    case Config.module_get(Sanbase, :deployment_env) do
      "stage" -> "preview-stage.santiment.net"
      "dev" -> "preview-stage.santiment.net"
      _ -> "preview.santiment.net"
    end
  end

  defp is_image?(response) do
    content_type =
      response.headers
      |> Enum.into(%{})
      |> Map.get("Content-Type")

    content_type == "image/jpeg"
  end

  defp sanbase_bot_id() do
    Sanbase.Repo.get_by(User, email: User.sanbase_bot_email()).id
  end

  defp can_manage_channel?(%Nostrum.Struct.Interaction{
         user: %{id: discord_user_id},
         guild_id: guild_id,
         channel_id: channel_id
       }) do
    with {:ok, guild} <- Nostrum.Cache.GuildCache.get(guild_id),
         {:ok, member} <- Nostrum.Api.get_guild_member(guild_id, discord_user_id) do
      :manage_channels in Nostrum.Struct.Guild.Member.guild_channel_permissions(
        member,
        guild,
        channel_id
      )
    end
  end

  defp get_guild_channel(nil, _), do: {nil, nil}
  defp get_guild_channel(_, nil), do: {nil, nil}

  defp get_guild_channel(guild_id, channel_id) do
    with {:ok, guild} <- Nostrum.Cache.GuildCache.get(guild_id),
         {:ok, channel} <- Nostrum.Cache.ChannelCache.get(channel_id) do
      {guild.name, channel.name}
    else
      _ -> {nil, nil}
    end
  end

  defp handle_pin_unpin_error(false, action, interaction) do
    interaction_msg(
      interaction,
      "You don't have enough permissions to #{action} queries, <@#{interaction.user.id}>",
      %{flags: @ephemeral_message_flags}
    )
  end

  defp handle_pin_unpin_error(result, _action, _interaction) do
    result
  end

  defp projects do
    from(
      p in Sanbase.Project,
      left_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      order_by: latest_cmc.rank,
      select: %{slug: p.slug, name: p.name, ticker: p.ticker}
    )
    |> Sanbase.Repo.all()
  end

  defp fetch_chart_files(metric, slug) do
    now =
      Timex.shift(Timex.now(), minutes: 10)
      |> Sanbase.DateTimeUtils.round_datetime(second: 600)
      |> Timex.set(microsecond: {0, 0})

    year_ago = Timex.shift(now, years: -1) |> Timex.set(microsecond: {0, 0})

    now_iso = DateTime.to_iso8601(now)
    year_ago_iso = DateTime.to_iso8601(year_ago)

    settings_json = Jason.encode!(%{slug: slug, from: year_ago_iso, to: now_iso})

    metrics = if metric == "price_usd", do: [metric], else: ["price_usd", metric]
    wax = Enum.with_index(metrics) |> Enum.into(%{}) |> Map.values()

    widgets_json =
      Jason.encode!([
        %{widget: "ChartWidget", wm: metrics, whm: [], wax: wax, wpax: [], wc: ["#26C953"]}
      ])

    url = URI.encode("/charts?settings=#{settings_json}&widgets=#{widgets_json}")

    {:ok, short_url} = Sanbase.ShortUrl.create(%{full_url: url})
    chart = "https://#{img_prefix_url()}/chart/#{short_url.short_url}"

    HTTPoison.get(chart, [basic_auth_header()])
    |> case do
      {:ok, response} ->
        if is_image?(response) do
          [%{body: response.body, name: "chart_#{short_url.short_url}.jpeg"}]
        else
          []
        end

      _ ->
        []
    end
  end

  defp slugs() do
    Sanbase.Cache.get_or_store(:discord_slugs, fn ->
      Sanbase.Cache.get_or_store(:discord_assets, fn -> projects() end)
      |> Enum.map(& &1.slug)
    end)
  end

  defp autocomplete_projects(interaction, value) do
    projects = Sanbase.Cache.get_or_store(:discord_assets, fn -> projects() end)
    value = String.downcase(value)

    choices =
      projects
      |> Enum.filter(fn project ->
        (not is_nil(project.name) and String.starts_with?(String.downcase(project.name), value)) or
          (not is_nil(project.ticker) and
             String.starts_with?(String.downcase(project.ticker), value)) or
          (not is_nil(project.slug) and String.starts_with?(String.downcase(project.slug), value))
      end)
      |> Enum.reject(&is_nil(&1.slug))
      |> Enum.map(fn project ->
        %{name: "#{project.ticker} | #{project.name}", value: project.slug}
      end)
      |> Enum.take(25)

    response = %{
      type: 8,
      data: %{
        choices: choices
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  defp autocomplete_metrics(interaction, value, slug) do
    metrics =
      if slug && slug in slugs() do
        Sanbase.Cache.get_or_store("discord_metrics_" <> slug, fn ->
          Sanbase.Metric.available_metrics_for_selector(%{slug: slug}) |> elem(1)
        end)
      else
        Sanbase.Cache.get_or_store(:discord_metrics, fn -> Sanbase.Metric.available_metrics() end)
      end

    value = String.downcase(value)

    metrics =
      if String.length(value) <= 2 do
        Enum.filter(metrics, fn metric -> String.starts_with?(metric, value) end)
      else
        Enum.filter(metrics, fn metric -> String.contains?(metric, value) end)
      end

    choices =
      metrics
      |> Enum.sort()
      |> Enum.map(fn metric -> %{name: metric, value: metric} end)
      |> Enum.take(25)

    response = %{
      type: 8,
      data: %{
        choices: choices
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  defp basic_auth_header() do
    credentials =
      (System.get_env("GRAPHQL_BASIC_AUTH_USERNAME") <>
         ":" <> System.get_env("GRAPHQL_BASIC_AUTH_PASSWORD"))
      |> Base.encode64()

    {"Authorization", "Basic #{credentials}"}
  end
end
