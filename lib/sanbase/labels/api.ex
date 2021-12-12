defmodule Sanbase.Labels.Api do
  @topic "label_changes"

  def add_labels_to_address(user, address, labels) do
    for label <- labels do
      data = %{
        type: "SINGLE",
        event: "CREATE",
        blockchain: deduce_blockchain(address),
        address: address,
        label: %{
          key: label,
          owner: create_owner_name(user),
          owner_id: user.id
        },
        event_dt: DateTime.to_iso8601(DateTime.utc_now()),
        change_reason: %{}
      }

      key = label <> data.event_dt
      {key, Jason.encode!(data)}
    end
    |> Sanbase.KafkaExporter.send_data_to_topic_from_current_process(@topic)
  end

  defp deduce_blockchain(address), do: "ethereum"

  defp create_owner_name(user) do
    if user.username do
      if String.starts_with?(user.username, "0x") do
        "0x" <> String.slice(user.username, -4, 4)
      else
        user.username
      end
    else
      generate_username(user.id)
    end
  end

  def generate_username(user_id) do
    :crypto.hash(:sha256, to_string(user_id))
    |> Base.encode16()
    |> binary_part(0, 6)
  end
end
