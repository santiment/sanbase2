defmodule Sanbase.DiscordBot.CodeHandler do
  @moduledoc false
  alias Nostrum.Struct.Component.ActionRow
  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.TextInput
  alias Nostrum.Struct.Interaction
  alias Sanbase.DiscordBot.AiGenCode
  alias Sanbase.DiscordBot.AiServer
  alias Sanbase.DiscordBot.LegacyCommandHandler
  alias Sanbase.DiscordBot.Utils

  require Logger

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
      Map.new(interaction.data.options, fn option -> {option.name, option.value} end)

    if focused_option do
      autocomplete(interaction, focused_option.name)
    else
      with {:ok, metadata_from_options} <- metadata_from_options(options_map),
           metadata = Map.merge(metadata, metadata_from_options),
           :ok <- check_from_to(interaction, metadata) do
        summarize_channel_or_thread(interaction, metadata, options_map)
      else
        {:error, :from_to_check} ->
          send_error_message(
            interaction,
            "The 'to' datetime should be greater than the 'from' datetime."
          )

        {:error, error} ->
          send_error_message(interaction, error)

        _ ->
          generic_error_message(interaction)
      end
    end
  end

  @spec handle_interaction(
          String.t(),
          Interaction.t(),
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
        Logger.error("Failed to generate program for question: #{option.value}, #{inspect(error)}")

        generic_error_message(interaction)
    end
  end

  @spec handle_interaction(
          String.t(),
          Interaction.t(),
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
        Logger.error("Failed to generate program with id #{old_ai_gen_code.id}: #{inspect(error)}")

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
      LegacyCommandHandler.get_guild_channel(
        interaction.guild_id,
        interaction.channel_id
      )

    user_is_team_member =
      LegacyCommandHandler.santiment_guild_id()
      |> Nostrum.Api.get_guild_member(interaction.user.id)
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
      is_thread: thread?(interaction.channel),
      guild_name: guild_name,
      discord_user: interaction.user.username <> interaction.user.discriminator,
      user_is_team_member: user_is_team_member
    }
  end

  def metadata_from_options(options_map) do
    {:ok, channel} = Nostrum.Api.get_channel(options_map["channel_or_thread"])
    from_dt = text_to_datetime(options_map["from_dt"])
    to_dt = text_to_datetime(options_map["to_dt"])

    cond do
      :unsupported_datetime_representation == from_dt ->
        {:error, "Invalid `from` datetime option"}

      :unsupported_datetime_representation == to_dt ->
        {:error, "Invalid `to` datetime option"}

      true ->
        {:ok,
         %{
           channel: to_string(channel.id),
           channel_name: channel.name,
           is_thread: thread?(channel),
           from_dt: from_dt |> DateTime.to_unix() |> to_string(),
           to_dt: to_dt |> DateTime.to_unix() |> to_string()
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
    choices = Enum.map(choices, fn choice -> %{name: choice, value: choice} end)

    response = %{
      type: 8,
      data: %{
        choices: choices
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  # helpers

  defp summarize_channel_or_thread(interaction, metadata, options_map) do
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
            Logger.error("Failed to summarize channel: #{metadata.channel_name}, #{inspect(error)}")

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
            Logger.error("Failed to summarize thread: #{metadata.channel_name}, #{inspect(error)}")

            generic_error_message(interaction)
        end

      _ ->
        generic_error_message(interaction)
    end
  end

  defp check_from_to(interaction, metadata) do
    if metadata[:to_dt] > metadata[:from_dt] do
      :ok
    else
      content = """
      The 'to' datetime should be greater than the 'from' datetime.
      """

      Utils.handle_interaction_response(interaction, content, [])

      {:error, :from_to_check}
    end
  end

  defp send_error_message(interaction, error) do
    content = """
    #{error}
    """

    Utils.handle_interaction_response(interaction, content, [])
  end

  defp thread?(%Nostrum.Struct.Channel{type: 11}) do
    true
  end

  defp thread?(_), do: false

  defp create_modal(interaction, id) do
    changes_input =
      TextInput.text_input("Changes", "changes_" <> id,
        placeholder: "What changes do you want to make?",
        style: 2,
        required: true
      )

    ar = ActionRow.put(ActionRow.action_row(), changes_input)

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

  defp text_to_datetime("now"), do: DateTime.utc_now()
  defp text_to_datetime("yesterday"), do: Timex.shift(DateTime.utc_now(), days: -1)
  defp text_to_datetime("1 day ago"), do: Timex.shift(DateTime.utc_now(), days: -1)
  defp text_to_datetime("2 days ago"), do: Timex.shift(DateTime.utc_now(), days: -2)
  defp text_to_datetime("3 days ago"), do: Timex.shift(DateTime.utc_now(), days: -3)
  defp text_to_datetime("4 days ago"), do: Timex.shift(DateTime.utc_now(), days: -4)
  defp text_to_datetime("5 days ago"), do: Timex.shift(DateTime.utc_now(), days: -5)
  defp text_to_datetime("6 days ago"), do: Timex.shift(DateTime.utc_now(), days: -6)
  defp text_to_datetime("last week"), do: Timex.shift(DateTime.utc_now(), weeks: -1)
  defp text_to_datetime("last 2 weeks"), do: Timex.shift(DateTime.utc_now(), weeks: -14)
  defp text_to_datetime("last month"), do: Timex.shift(DateTime.utc_now(), months: -1)
  defp text_to_datetime(_), do: :unsupported_datetime_representation
end
