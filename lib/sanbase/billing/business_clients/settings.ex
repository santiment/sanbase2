defmodule Sanbase.Billing.BusinessClients.Settings do
  @moduledoc ~s"""
  The editable parameters of the Business Clients page: which plans count as business,
  which email domains are free providers, the churn window and the renewal rules, and
  the log entry types.

  Stored as one row so a change applies to every number at once. `get/0` always returns
  every key - a key missing from the stored map falls back to its default - so a new
  parameter added here needs no data migration.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo

  @key "default"

  @free_email_domains ~w(
    gmail.com googlemail.com yahoo.com yahoo.co.uk ymail.com rocketmail.com hotmail.com
    hotmail.co.uk outlook.com live.com msn.com icloud.com me.com mac.com aol.com
    protonmail.com protonmail.ch proton.me pm.me gmx.com gmx.de gmx.net web.de mail.com
    yandex.com yandex.ru mail.ru inbox.ru list.ru bk.ru rambler.ru qq.com 163.com 126.com
    sina.com zoho.com tutanota.com tuta.io hey.com fastmail.com inbox.com naver.com
    hanmail.net seznam.cz abv.bg mail.bg free.fr orange.fr laposte.net libero.it
    t-online.de wp.pl o2.pl interia.pl
  )

  @defaults %{
    # A trailing `*` matches any plan name with that prefix.
    business_plan_patterns:
      ~w(BUSINESS_PRO BUSINESS_MAX ENTERPRISE CUSTOM CUSTOM_* INSTITUTIONAL*),
    # Plans that count as business only when the user's email is not a free provider.
    business_email_plan_names: ~w(PRO MAX),
    business_email_product_ids: [2],
    free_email_domains: @free_email_domains,
    churn_window_months: 12,
    renewal_intervals: ~w(year),
    renewal_grace_days: 30,
    renewal_upgrades_full_value: true,
    usage_window_days: 30,
    issue_types: [
      "Complaint",
      "Product / data issue",
      "Payment issue",
      "No response",
      "Usage concern",
      "Renewal discussion",
      "Retention action",
      "Positive signal",
      "Other"
    ],
    types_without_severity: ["Retention action", "Positive signal"],
    retention_action_type: "Retention action"
  }

  @list_keys ~w(business_plan_patterns business_email_plan_names business_email_product_ids
                free_email_domains renewal_intervals issue_types types_without_severity)a

  schema "business_client_settings" do
    field(:key, :string)
    field(:settings, :map, default: %{})

    belongs_to(:updated_by, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc ~s"""
  The current parameters, every key present, atom keyed.
  """
  @spec get() :: map()
  def get do
    stored =
      case Repo.get_by(__MODULE__, key: @key) do
        nil -> %{}
        %__MODULE__{settings: settings} -> settings
      end

    Enum.reduce(@defaults, %{}, fn {key, default}, acc ->
      Map.put(acc, key, Map.get(stored, Atom.to_string(key), default))
    end)
  end

  @doc ~s"""
  When and by whom the parameters were last changed, `nil` while the defaults apply.
  """
  @spec last_change() :: %{updated_at: DateTime.t(), updated_by_id: integer() | nil} | nil
  def last_change do
    case Repo.get_by(__MODULE__, key: @key) do
      nil -> nil
      row -> %{updated_at: row.updated_at, updated_by_id: row.updated_by_id}
    end
  end

  @doc ~s"""
  Validates and stores new parameters. Only the given keys change.

  Returns the full parameter map like `get/0`, or a changeset with the errors.
  """
  @spec update(map(), integer() | nil) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def update(attrs, updated_by_id) do
    changeset = validate(attrs)

    if changeset.valid? do
      row = Repo.get_by(__MODULE__, key: @key) || %__MODULE__{key: @key}

      # Only the changed keys are stored: a key never edited keeps following its
      # default, so a later change to a default reaches it.
      changed = Map.new(changeset.changes, fn {key, value} -> {Atom.to_string(key), value} end)
      merged = Map.merge(row.settings || %{}, changed)

      row
      |> change(settings: merged, updated_by_id: updated_by_id)
      |> Repo.insert_or_update()
      |> case do
        {:ok, _} -> {:ok, get()}
        {:error, error} -> {:error, error}
      end
    else
      {:error, changeset}
    end
  end

  @doc ~s"""
  A changeset over the parameters, for forms. Lists may be given as comma or newline
  separated text.
  """
  @spec validate(map()) :: Ecto.Changeset.t()
  def validate(attrs) do
    types = %{
      business_plan_patterns: {:array, :string},
      business_email_plan_names: {:array, :string},
      business_email_product_ids: {:array, :integer},
      free_email_domains: {:array, :string},
      churn_window_months: :integer,
      renewal_intervals: {:array, :string},
      renewal_grace_days: :integer,
      renewal_upgrades_full_value: :boolean,
      usage_window_days: :integer,
      issue_types: {:array, :string},
      types_without_severity: {:array, :string},
      retention_action_type: :string
    }

    {get(), types}
    |> cast(normalize_lists(attrs), Map.keys(types))
    |> validate_number(:churn_window_months, greater_than: 0, less_than_or_equal_to: 36)
    |> validate_number(:renewal_grace_days, greater_than_or_equal_to: 0, less_than: 366)
    |> validate_number(:usage_window_days, greater_than: 0, less_than: 366)
    |> validate_subset(:renewal_intervals, ~w(month year))
    |> validate_length(:issue_types, min: 1)
    |> validate_retention_type()
    |> update_change(:free_email_domains, fn domains ->
      domains |> Enum.map(&String.downcase(String.trim(&1))) |> Enum.uniq()
    end)
  end

  defp validate_retention_type(changeset) do
    types = get_field(changeset, :issue_types) || []
    retention = get_field(changeset, :retention_action_type)

    if retention in types do
      changeset
    else
      add_error(changeset, :retention_action_type, "must be one of the issue types")
    end
  end

  defp normalize_lists(attrs) do
    Map.new(attrs, fn {key, value} ->
      key = to_string(key)

      if key in Enum.map(@list_keys, &Atom.to_string/1) and is_binary(value) do
        {key,
         value
         |> String.split([",", "\n"])
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == ""))}
      else
        {key, value}
      end
    end)
  end
end
