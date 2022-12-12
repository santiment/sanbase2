defmodule Sanbase.Discord.CommandHandler do
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard.DiscordDashboard
  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}
  alias Sanbase.Utils.Config

  @prefix "!q"
  @mock_role_id 1
  @max_size 1800

  def is_command?(content) do
    String.starts_with?(content, @prefix)
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

  def handle_interaction("run", interaction) do
    interaction_ack(interaction)

    {name, sql} = parse_modal_component(interaction)
    args = get_additional_info(interaction)

    with {:ok, exec_result, dashboard, panel_id} <- compute_and_save(name, sql, [], args) do
      content = format_table(name, exec_result, to_string(interaction.user.id))
      components = [action_row(panel_id)]
      embeds = create_chart_embed(exec_result, dashboard, panel_id)

      edit_interaction_response(interaction, content, components, embeds)
      |> maybe_add_stats?(interaction, exec_result, content, components, embeds)
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
        embeds: [embed]
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

    with {:ok, execution_result, dashboard, _dashboard_id} <-
           DiscordDashboard.execute(sanbase_bot_id(), panel_id) do
      panel = List.first(dashboard.panels)
      content = format_table(panel.name, execution_result, to_string(interaction.user.id))
      components = [action_row(panel_id)]
      embeds = create_chart_embed(execution_result, dashboard, panel_id)

      edit_interaction_response(interaction, content, components, embeds)
      |> maybe_add_stats?(interaction, execution_result, content, components, embeds)
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
    with {:ok, dd} <- DiscordDashboard.pin(panel_id) do
      interaction_msg(interaction, "<@#{interaction.user.id}> pinned #{dd.name}")
    end
  end

  def handle_interaction("unpin", interaction, panel_id) do
    with {:ok, dd} <- DiscordDashboard.unpin(panel_id) do
      interaction_msg(interaction, "<@#{interaction.user.id}> unpinned #{dd.name}")
    end
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

      interaction_msg(interaction, content)
    else
      _ -> interaction_msg(interaction, "Query is removed from our database")
    end
  end

  def handle_command("run", name, sql, msg) do
    {:ok, loading_msg} = Api.create_message(msg.channel_id, content: "Your query is running ...")

    args = get_additional_info_msg(msg)

    with {:ok, exec_result, dd, panel_id} <- compute_and_save(name, sql, [], args) do
      content = format_table(name, exec_result, to_string(msg.author.id))
      components = [action_row(panel_id)]
      embeds = create_chart_embed(exec_result, dd, panel_id)

      Api.edit_message(msg.channel_id, loading_msg.id,
        content: content,
        components: components,
        embeds: embeds
      )
      |> maybe_add_stats?(msg, exec_result, content, components, embeds)
    else
      {:execution_error, reason} ->
        content = sql_execution_error(reason, msg.author.id, name)
        Api.edit_message(msg.channel_id, loading_msg.id, content: content)
    end
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

    Nostrum.Api.create_message(msg.channel_id, content: content)
  end

  def handle_command("invalid_command", msg) do
    Nostrum.Api.create_message(msg.channel_id,
      content: "<:bangbang:1045078993604452465> Invalid command entered!"
    )
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

  def format_table(name, %{rows: []}, discord_user) do
    """
    #{name}: <@#{discord_user}>

    0 rows in set.
    """
  end

  def format_table(name, response, discord_user) do
    max_rows = response.rows |> Enum.take(1) |> max_rows()
    rows = response.rows |> Enum.take(max_rows - 1)
    table = TableRex.quick_render!(rows, response.columns)

    """
    #{name}: <@#{discord_user}>

    ```
    #{table}
    ```
    """
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
    Nostrum.Api.create_interaction_response(interaction, %{type: 5})
  end

  defp interaction_msg(interaction, content) do
    data = %{
      type: 4,
      data: %{
        content: content
      }
    }

    Nostrum.Api.create_interaction_response(interaction, data)
  end

  defp interaction_message_response(content) do
    %{
      type: 4,
      data: %{
        content: content
      }
    }
  end

  def edit_interaction_response(interaction, content) do
    Nostrum.Api.edit_interaction_response(interaction, %{content: content})
  end

  def edit_interaction_response(interaction, content, components) do
    Nostrum.Api.edit_interaction_response(interaction, %{content: content, components: components})
  end

  def edit_interaction_response(interaction, content, components, embeds) do
    Nostrum.Api.edit_interaction_response(interaction, %{
      content: content,
      components: components,
      embeds: embeds
    })
  end

  defp parse_modal_component(interaction) do
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

  defp get_additional_info(interaction) do
    %{
      discord_user: to_string(interaction.user.id),
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator,
      discord_message_id: to_string(interaction.id),
      pinned: false
    }
  end

  defp get_additional_info_msg(msg) do
    %{
      discord_user: to_string(msg.author.id),
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
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
    run_button = Button.button(label: "Rerun 🚀", custom_id: "rerun" <> "_" <> panel_id, style: 3)
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

  def create_chart_embed(exec_result, dd, panel_id) do
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

      map =
        data_columns
        |> Enum.with_index()
        |> Enum.into(%{}, fn {_, idx} -> {to_string(idx), %{node: "bar"}} end)

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

  def img_prefix_url() do
    case Config.module_get(Sanbase, :deployment_env) do
      "stage" -> "preview-stage.santiment.net"
      "dev" -> "preview-stage.santiment.net"
      _ -> "preview.santiment.net"
    end
  end

  def is_image?(response) do
    content_type =
      response.headers
      |> Enum.into(%{})
      |> Map.get("Content-Type")

    content_type == "image/jpeg"
  end

  defp sanbase_bot_id() do
    Sanbase.Repo.get_by(User, email: User.sanbase_bot_email()).id
  end
end
