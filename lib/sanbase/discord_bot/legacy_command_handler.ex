defmodule Sanbase.DiscordBot.LegacyCommandHandler do
  import Nostrum.Struct.Embed
  import Ecto.Query

  require Logger

  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  alias Sanbase.Accounts.User
  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}
  alias Sanbase.Utils.Config

  @prefix "!q "
  @ai_prefix "!ai "
  @docs_prefix "!docs "
  # @mock_role_id 1
  @max_size 1800
  @ephemeral_message_flags 64
  @local_bot_id 1_039_543_550_326_612_009
  @stage_bot_id 1_039_177_602_197_372_989
  @prod_bot_id 1_039_814_526_708_764_742
  @prod_pro_roles [532_833_809_947_951_105, 409_637_386_012_721_155]
  @local_pro_roles [854_304_500_402_880_532]
  @local_guild_id 852_836_083_381_174_282
  @santiment_guild_id 334_289_660_698_427_392

  def bot_id() do
    case Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_bot_id
      "stage" -> @stage_bot_id
      _ -> @prod_bot_id
    end
  end

  def pro_roles() do
    case Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_pro_roles
      _ -> @prod_pro_roles
    end
  end

  def santiment_guild_id() do
    case Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_guild_id
      _ -> @santiment_guild_id
    end
  end

  def command?(content) do
    String.starts_with?(content, @prefix)
  end

  def ai_command?(content) do
    String.starts_with?(content, @ai_prefix)
  end

  def docs_command?(content) do
    String.starts_with?(content, @docs_prefix)
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

  # private

  def get_guild_channel(nil, _), do: {nil, nil}
  def get_guild_channel(_, nil), do: {nil, nil}

  def get_guild_channel(guild_id, channel_id) do
    guild_name =
      case Nostrum.Cache.GuildCache.get(guild_id) do
        {:ok, guild} ->
          guild.name

        _ ->
          case Nostrum.Api.get_guild(guild_id) do
            {:ok, guild} -> guild.name
            _ -> nil
          end
      end

    channel_name =
      case Nostrum.Cache.ChannelCache.get(channel_id) do
        {:ok, channel} ->
          channel.name

        _ ->
          case Nostrum.Api.get_channel(channel_id) do
            {:ok, channel} -> channel.name
            _ -> nil
          end
      end

    {guild_name, channel_name}
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

  defp header(name, discord_user) do
    """
    #{name}: <@#{discord_user}>
    """
  end

  defp format_table(name, %{rows: []}, discord_user) do
    """
    #{name}: <@#{discord_user}>

    0 rows in set.
    """
  end

  defp format_table(name, response, discord_user) do
    max_rows = response.rows |> Enum.take(1) |> max_rows()

    table =
      if max_rows == 0 and length(response.columns) == 1 do
        String.slice(response.rows |> hd() |> hd(), 0, 1900)
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

  defp get_execution_summary(qe) do
    ed = qe.execution_details

    """
    ```
    #{ed["result_rows"]} rows in set. Elapsed: #{ed["query_duration_ms"] / 1000} sec.
    Processed #{Number.Human.number_to_human(ed["read_rows"])} rows, #{ed["read_gb"]} GB
    ```
    """
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
    case Sanbase.Dashboard.QueryExecution.get_execution_stats(exec_result.clickhouse_query_id) do
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
    case Sanbase.Dashboard.QueryExecution.get_execution_stats(exec_result.clickhouse_query_id) do
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

      map =
        data_columns
        |> Enum.with_index()
        |> Enum.into(%{}, fn {name, idx} -> {to_string(idx), %{node: chart_type(name)}} end)

      settings =
        %{wm: data_columns, ws: map}
        |> Jason.encode!()
        |> URI.encode()

      chart =
        "https://#{img_prefix_url()}/chart/dashboard/#{dd.id}/#{panel_id}?settings=#{settings}"

      maybe_create_embed(chart, dd.name)
    else
      []
    end
  end

  defp chart_type(column_name) do
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

  defp maybe_create_embed(chart, name) do
    HTTPoison.get(chart)
    |> case do
      {:ok, response} ->
        if image?(response) do
          %Embed{}
          |> put_title(name)
          |> put_url(chart)
          |> put_image(chart)
          |> List.wrap()
        else
          []
        end

      _ ->
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

  defp image?(response) do
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
        if image?(response) do
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
