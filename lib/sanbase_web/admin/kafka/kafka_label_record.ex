defmodule Sanbase.Model.Kafka.KafkaLabelRecord do
  use Ecto.Schema
  import Ecto.Changeset
  require Logger

  schema "kafka_label_records" do
    field(:topic, :string)
    field(:sign, :integer)
    field(:address, :string)
    field(:blockchain, :string)
    field(:label, :string)
    field(:metadata, :string)
    field(:datetime, :naive_datetime)
  end

  @fields [:topic, :sign, :address, :blockchain, :label, :metadata, :datetime]
  @required_fields @fields -- [:metadata]

  def changeset(struct, attrs \\ %{}) do
    struct |> cast(attrs, @fields) |> validate_required(@required_fields)
  end
end

defmodule SanbaseWeb.ExAdmin.Kafka.KafkaLabelRecord do
  use ExAdmin.Register
  require Sanbase.Utils.Config, as: Config
  @producer Config.module_get(Sanbase.KafkaExporter, :producer)

  register_resource Sanbase.Model.Kafka.KafkaLabelRecord do
    form label do
      inputs do
        content do
          """
          Example: 0x123, bitcoin, centralized_exchange, {"owner": "Binance", "isDex": false}, <optional iso8601 datetime>
          """
        end

        input(label, :csv,
          type: :text,
          label:
            "CSV Format: address, blockchain, label, metadata ({} for empty), <optional iso8601 datetime>"
        )
      end
    end

    controller do
      before_filter(:process_csv, only: [:create, :update])
      after_filter(:clean_from_kafka, only: [:destroy])
    end
  end

  def clean_from_kafka(conn, _params, resource, :destroy) do
    %Sanbase.Model.Kafka.KafkaLabelRecord{
      address: address,
      blockchain: blockchain,
      label: label,
      metadata: metadata
    } = resource

    data = [
      [address, blockchain, label, metadata, DateTime.utc_now() |> DateTime.to_unix()]
    ]

    :ok = send_to_kafka(data, sign: -1)

    conn
  end

  @topic "manual-address-labels"
  def process_csv(conn, %{kafka_label_record: %{csv: csv}} = params) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    data =
      csv
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(fn row_str ->
        case String.split(row_str, ",", parts: 4) do
          [addr, chain, label, trailing] ->
            # Trailing is either metadata or metadata and datetime
            list = String.split(trailing, ",")

            {ts, metadata} =
              case List.last(list) |> String.trim() |> DateTime.from_iso8601() do
                {:ok, %DateTime{} = datetime, _} ->
                  {_, metadata} = list |> List.pop_at(-1)
                  {datetime |> DateTime.to_unix(), metadata |> Enum.join(",")}

                _ ->
                  {timestamp, trailing}
              end

            ([addr, chain, label] |> Enum.map(&String.trim/1)) ++
              [Jason.decode!(metadata), ts]

          [] ->
            []
        end
      end)
      |> Enum.reject(&(&1 == []))

    all_present? =
      Enum.reduce(data, true, fn [addr, chain, label, _, _], acc ->
        acc and (addr != "" and chain != "" and label != "")
      end)

    case all_present? do
      false ->
        Logger.warn("Exporing labels to kafka failed. Reason: There are missing fields")

        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "All fields except metadata are mandatory."
         ), %{params | kafka_label_record: %{}}}

      true ->
        Logger.info("Sending address labels to kafka imported via the admin panel...")

        with {_, :ok} <- {:kafka, send_to_kafka(data)},
             {_, {num, _}} when is_integer(num) <- {:postgres, store_in_postgres(data)} do
          {conn, params}
        else
          {:kafka, {:error, error}} ->
            error_msg = "Error exporting the labels to kafka. Reason: #{inspect(error)}"
            Logger.warn(error_msg)

            {Phoenix.Controller.put_flash(
               conn,
               :error,
               error_msg
             ), %{params | kafka_label_record: %{}}}

          {:postgres, _} ->
            error_msg = "The labels could not be stored in postrgres"
            Logger.warn(error_msg)

            {Phoenix.Controller.put_flash(
               conn,
               :error,
               error_msg
             ), %{params | kafka_label_record: %{}}}
        end
    end
  end

  defp send_to_kafka(data, opts \\ []) do
    Logger.info("Exporting labels to kafka via the admin panel...")

    sign = Keyword.get(opts, :sign, 1)

    kafka_data =
      Enum.map(data, fn [address, blockchain, label, metadata, timestamp] ->
        %{
          sign: sign,
          address: address,
          blockchain: blockchain,
          label: label,
          metadata: metadata,
          timestamp: timestamp
        }
      end)
      |> Enum.map(&{Sanbase.Cache.hash(&1), Jason.encode!(&1)})

    @producer.send_data(@topic, kafka_data)
  end

  defp to_dt_struct(dt_str) when is_binary(dt_str),
    do: Sanbase.DateTimeUtils.from_iso8601!(dt_str)

  defp to_dt_struct(timestamp) when is_integer(timestamp),
    do: DateTime.from_unix!(timestamp)

  defp to_dt_struct(%DateTime{} = dt), do: dt

  defp store_in_postgres(data) do
    Logger.info("Exporting labels to postgres via the admin panel...")

    insert_data =
      Enum.map(data, fn [address, blockchain, label, metadata, timestamp] ->
        %{
          topic: @topic,
          sign: 1,
          address: address,
          blockchain: blockchain,
          label: label,
          metadata: metadata |> Jason.encode!(),
          datetime:
            timestamp |> to_dt_struct() |> DateTime.truncate(:second) |> DateTime.to_naive()
        }
      end)

    Sanbase.Repo.insert_all(Sanbase.Model.Kafka.KafkaLabelRecord, insert_data,
      on_conflict: :nothing
    )
  end
end
