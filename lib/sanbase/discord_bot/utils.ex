defmodule Sanbase.DiscordBot.Utils do
  @moduledoc """
  Discord bot utils
  """

  alias Nostrum.Struct.Interaction

  @ephemeral_message_flags 64

  @spec edit_interaction_response(
          Interaction.t(),
          String.t(),
          list()
        ) :: {:ok, Nostrum.Struct.Message.t()} | {:error, any()}
  def edit_interaction_response(interaction, content, components) do
    Nostrum.Api.edit_interaction_response(interaction, %{
      content: trim_message(content, 1950),
      components: components
    })
  end

  def handle_interaction_response(interaction, content, components) do
    messages = split_message(content, 1950)

    case messages do
      [first_message | remaining_messages] ->
        # Send the initial interaction response
        Nostrum.Api.edit_interaction_response(interaction, %{
          content: first_message,
          components: components
        })

        # Send the follow-up messages
        Enum.each(remaining_messages, fn message ->
          Nostrum.Api.create_followup_message(interaction.token, %{
            content: message,
            components: components
          })
        end)
    end
  end

  @spec interaction_ack_visible(Interaction.t()) :: {:ok} | {:error, any()}
  def interaction_ack_visible(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{type: 5})
  end

  @spec interaction_ack(Interaction.t()) :: {:ok} | {:error, any()}
  def interaction_ack(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{
      type: 5,
      data: %{flags: @ephemeral_message_flags}
    })
  end

  @spec trim_message(String.t(), pos_integer()) :: String.t()
  def trim_message(message, max_length \\ 1950) do
    end_message =
      if String.starts_with?(String.trim_leading(message), "```") do
        "... (message truncated)```"
      else
        "... (message truncated)"
      end

    if String.length(message) > max_length do
      String.slice(message, 0, max_length) <> end_message
    else
      message
    end
  end

  @spec split_message(String.t(), pos_integer()) :: list(String.t())
  def split_message(content, max_length) do
    ~r/.{1,#{max_length}}/s
    |> Regex.scan(content)
    |> Enum.map(&Enum.at(&1, 0))
  end
end
