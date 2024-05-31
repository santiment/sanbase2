defmodule Sanbase.DiscordBot.CodeHandler do
  require Logger

  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}

  alias Sanbase.DiscordBot.AiGenCode
  alias Sanbase.DiscordBot.Utils
  alias Sanbase.DiscordBot.AiServer

  @team_role_id 409_637_386_012_721_155
  @local_team_role_id 854_304_500_402_880_532

  @spec team_role_id() :: integer()
  def team_role_id do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_team_role_id
      _ -> @team_role_id
    end
  end

  def handle_interaction("summary", interaction, metadata) do
    Utils.interaction_ack_visible(interaction)

    focused_option =
      interaction.data.options
      |> Enum.filter(& &1.focused)
      |> List.first()

    options_map =
      interaction.data.options |> Enum.into(%{}, fn option -> {option.name, option.value} end)

    if focused_option do
      autocomplete(interaction, focused_option.name)
    else
      case metadata_from_options(options_map) do
        {:error, error} ->
          content = """
          #{error}
          """

          Utils.handle_interaction_response(interaction, content, [])

        {:ok, metadata_from_options} ->
          metadata = Map.merge(metadata, metadata_from_options)

          if metadata[:to_dt] <= metadata[:from_dt] do
            content = """
            The 'to' datetime should be greater than the 'from' datetime.
            """

            Utils.handle_interaction_response(interaction, content, [])
          else
            case metadata.is_thread do
              false ->
                case AiServer.summarize_channel(
                       metadata.channel,
                       Map.take(metadata, [:from_dt, :to_dt])
                     ) do
                  {:ok, summary} ->
                    content = """
                    📝 Summary for channel: #{metadata.channel_name} from: `#{options_map["from_dt"]}`, to: `#{options_map["to_dt"]}`

                    #{summary}
                    """

                    Utils.handle_interaction_response(interaction, content, [])

                  {:error, error} ->
                    Logger.error(
                      "Failed to summarize channel: #{metadata.channel_name}, #{inspect(error)}"
                    )

                    generic_error_message(interaction)
                end

              true ->
                case AiServer.summarize_thread(
                       metadata.channel,
                       Map.take(metadata, [:from_dt, :to_dt])
                     ) do
                  {:ok, summary} ->
                    content = """
                    📝 Summary for thread: #{metadata.channel_name} from: `#{options_map["from_dt"]}`, to: `#{options_map["to_dt"]}`

                    #{summary}
                    """

                    Utils.handle_interaction_response(interaction, content, [])

                  {:error, error} ->
                    Logger.error(
                      "Failed to summarize thread: #{metadata.channel_name}, #{inspect(error)}"
                    )

                    generic_error_message(interaction)
                end

              _ ->
                generic_error_message(interaction)
            end
          end
      end
    end
  end

  @spec handle_interaction(
          String.t(),
          Nostrum.Struct.Interaction.t(),
          map()
        ) :: {:ok, any()} | {:error, any()}
  def handle_interaction("code", interaction, metadata) do
    Utils.interaction_ack_visible(interaction)

    [option] = interaction.data.options

    case AiServer.find_or_generate_program(option.value, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        Utils.edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error(
          "Failed to generate program for question: #{option.value}, #{inspect(error)}"
        )

        generic_error_message(interaction)
    end
  end

  @spec handle_interaction(
          String.t(),
          Nostrum.Struct.Interaction.t(),
          String.t(),
          map()
        ) :: {:ok, any()} | {:error, any()}
  def handle_interaction("save-program", interaction, id, _metadata) do
    Utils.interaction_ack_visible(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    AiServer.save_program(ai_gen_code)

    content = """
    🟢 Program saved successfully!
    """

    Utils.edit_interaction_response(interaction, content, [])
  end

  def handle_interaction("show-program", interaction, id, _metadata) do
    Utils.interaction_ack(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    content = """
    ```python
    #{ai_gen_code.program}
    ```
    """

    Utils.edit_interaction_response(interaction, content, [action_row(ai_gen_code)])
  end

  def handle_interaction("show-program-result", interaction, id, _metadata) do
    Utils.interaction_ack(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    content = """
    ```
    #{ai_gen_code.program_result}
    ```
    """

    Utils.edit_interaction_response(interaction, content, [])
  end

  def handle_interaction("generate-program", interaction, id, metadata) do
    Utils.interaction_ack_visible(interaction)

    old_ai_gen_code = AiGenCode.by_id(id)

    case AiServer.generate_program(old_ai_gen_code.question, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        Utils.edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error(
          "Failed to generate program with id #{old_ai_gen_code.id}: #{inspect(error)}"
        )

        generic_error_message(interaction)
    end
  end

  def handle_interaction("program-changes", interaction, id, metadata) do
    Utils.interaction_ack_visible(interaction)

    changes =
      interaction.data.components
      |> List.first()
      |> Map.get(:components)
      |> List.first()
      |> Map.get(:value)

    old_ai_gen_code = AiGenCode.by_id(id)

    case AiServer.change_program(old_ai_gen_code, changes, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        After the following changes:
        ```
        #{changes}
        ```

        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        Utils.edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error("Failed to change program with id #{old_ai_gen_code.id}: #{inspect(error)}")
        generic_error_message(interaction)
    end
  end

  def handle_interaction("change-program-modal", interaction, id, _metadata) do
    create_modal(interaction, id)
  end

  def access_denied(interaction) do
    Utils.interaction_ack_visible(interaction)

    content =
      "You don't have access to this command. The command is available only to Santiment team members."

    Utils.edit_interaction_response(interaction, content, [])
  end

  def generic_error_message(interaction) do
    content = "An errror occured. Please try again"
    Utils.edit_interaction_response(interaction, content, [])
  end

  def discord_metadata(interaction) do
    {guild_name, channel_name} =
      Sanbase.DiscordBot.LegacyCommandHandler.get_guild_channel(
        interaction.guild_id,
        interaction.channel_id
      )

    user_is_team_member =
      Nostrum.Api.get_guild_member(
        Sanbase.DiscordBot.LegacyCommandHandler.santiment_guild_id(),
        interaction.user.id
      )
      |> case do
        {:ok, member} ->
          team_role_id() in member.roles

        other ->
          Logger.error("Failed to get guild member: #{inspect(other)}")
          false
      end

    %{
      channel: to_string(interaction.channel_id),
      guild_id: to_string(interaction.guild_id),
      channel_name: channel_name,
      is_thread: is_thread?(interaction.channel),
      guild_name: guild_name,
      discord_user: interaction.user.username <> interaction.user.discriminator,
      user_is_team_member: user_is_team_member
    }
  end

  def metadata_from_options(options_map) do
    {:ok, channel} = Nostrum.Api.get_channel(options_map["channel_or_thread"])
    now = DateTime.utc_now()

    tranform_fns = %{
      "yesterday" => fn now -> Timex.shift(now, days: -1) end,
      "now" => fn now -> now end,
      "1 day ago" => fn now -> Timex.shift(now, days: -1) end,
      "2 days ago" => fn now -> Timex.shift(now, days: -2) end,
      "3 days ago" => fn now -> Timex.shift(now, days: -3) end,
      "4 days ago" => fn now -> Timex.shift(now, days: -4) end,
      "5 days ago" => fn now -> Timex.shift(now, days: -5) end,
      "6 days ago" => fn now -> Timex.shift(now, days: -6) end,
      "last week" => fn now -> Timex.shift(now, weeks: -1) end,
      "last 2 weeks" => fn now -> Timex.shift(now, weeks: -14) end,
      "last month" => fn now -> Timex.shift(now, months: -1) end
    }

    cond do
      options_map["from_dt"] not in Map.keys(tranform_fns) ->
        {:error, "Invalid `from` datetime option"}

      options_map["to_dt"] not in Map.keys(tranform_fns) ->
        {:error, "Invalid `to` datetime option"}

      options_map["from_dt"] in Map.keys(tranform_fns) and
          options_map["to_dt"] in Map.keys(tranform_fns) ->
        from_dt = tranform_fns[options_map["from_dt"]].(now)
        to_dt = tranform_fns[options_map["to_dt"]].(now)

        {:ok,
         %{
           channel: channel.id,
           channel_name: channel.name,
           is_thread: is_thread?(channel),
           from_dt: DateTime.to_unix(from_dt),
           to_dt: DateTime.to_unix(to_dt)
         }}
    end
  end

  def autocomplete(interaction, "from_dt") do
    choices = [
      "yesterday",
      "2 days ago",
      "3 days ago",
      "4 days ago",
      "5 days ago",
      "6 days ago",
      "last week",
      "2 weeks ago",
      "last month"
    ]

    do_autocomplete(interaction, choices)
  end

  def autocomplete(interaction, "to_dt") do
    choices = [
      "now",
      "yesterday",
      "2 days ago",
      "3 days ago",
      "4 days ago",
      "5 days ago",
      "6 days ago",
      "last week",
      "2 weeks ago",
      "last month"
    ]

    do_autocomplete(interaction, choices)
  end

  def do_autocomplete(interaction, choices) do
    choices = choices |> Enum.map(fn choice -> %{name: choice, value: choice} end)

    response = %{
      type: 8,
      data: %{
        choices: choices
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  # helpers

  defp is_thread?(%Nostrum.Struct.Channel{type: 11}) do
    true
  end

  defp is_thread?(_), do: false

  defp create_modal(interaction, id) do
    changes_input =
      TextInput.text_input("Changes", "changes_" <> id,
        placeholder: "What changes do you want to make?",
        style: 2,
        required: true
      )

    ar = ActionRow.action_row() |> ActionRow.put(changes_input)

    response = %{
      type: 9,
      data: %{
        custom_id: "program-changes_#{id}",
        title: "What changes do you want to make?",
        min_length: 1,
        max_length: 500,
        components: [ar]
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  defp action_row(ai_gen_code) do
    id = to_string(ai_gen_code.id)

    show_button =
      Button.button(label: "Show program 💻", custom_id: "show-program" <> "_" <> id, style: 3)

    result_button =
      Button.button(
        label: "Program result 📜",
        custom_id: "show-program-result" <> "_" <> id,
        style: 3
      )

    change_button =
      Button.button(
        label: "Change program 🛠️",
        custom_id: "change-program-modal" <> "_" <> id,
        style: 3
      )

    gen_button =
      Button.button(
        label: "Generate new program 🤖",
        custom_id: "generate-program" <> "_" <> id,
        style: 3
      )

    save_button =
      Button.button(label: "Save program 💾", custom_id: "save-program" <> "_" <> id, style: 3)

    ActionRow.action_row()
    |> ActionRow.append(show_button)
    |> ActionRow.append(result_button)
    |> ActionRow.append(change_button)
    |> ActionRow.append(gen_button)
    |> ActionRow.append(save_button)
  end
end
