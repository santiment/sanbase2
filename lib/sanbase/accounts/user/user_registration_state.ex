defmodule Sanbase.Accounts.User.RegistrationState do
  @moduledoc ~s"""
  The Registration State is a JSON field of the User that holds the current
  state of the registration process along with some metadata.

  The state is evolved like a state machine - given the current state and some
  action, the state can either evolve to a new state or be kept the same.
  """

  alias Sanbase.Accounts.EventEmitter
  alias Sanbase.Accounts.User
  alias __MODULE__.StateMachine

  @doc ~s"""
  Take a step forward in the registration progress by executing the given `action`.

  The new data is merged with the old data and this is stored in the map as well,
  so it can be used later.

  In some of the cases emit events like:
  If the state changes from not finished to finish, emit :register_user event
  """
  def forward(%User{registration_state: registration_state} = user, action, data) do
    current_state = Map.fetch!(registration_state, "state")

    old_data =
      Map.get(registration_state, "data", %{})
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    merged_data = Map.merge(old_data, data)

    case StateMachine.forward(current_state, action) do
      :keep_state ->
        :keep_state

      {:next_state, next_state} ->
        {:next_state, next_state, merged_data}
    end
    |> emit_event(user)
  end

  def is_registered(%User{registration_state: registration_state}) do
    registration_state["state"] == "finished"
  end

  def is_first_login(%User{registration_state: registration_state}, action)
      when action in ["eth_login", "email_login_verify"] do
    %{"state" => current_state} = registration_state

    # This is going to be used in case of eth_login and email_login_verify actions
    # In these cases, if this action is performed and the state is not finished, but
    # moves to `finished` after performing the action, then this can be treated
    # as first_login: true`
    current_state != "finished" and
      match?({:next_state, "finished"}, StateMachine.forward(current_state, action))
  end

  def login_to_finish_registration?(%User{registration_state: registration_state}) do
    registration_state["state"] == "wait_login_to_finish_registration"
  end

  defp emit_event(:keep_state, _), do: :keep_state

  defp emit_event({:next_state, "login_email_sent", data} = result, user) do
    EventEmitter.emit_event({:ok, user}, :send_email_login_link, data)

    result
  end

  defp emit_event({:next_state, "finished", data} = result, user) do
    EventEmitter.emit_event({:ok, user}, :register_user, data)

    result
  end

  defp emit_event(result, _user), do: result

  defmodule StateMachine do
    # In case the user is already registered, do nothing.
    def forward("finished", _), do: :keep_state

    def forward(_, "send_login_email"), do: {:next_state, "login_email_sent"}
    def forward(_, "google_oauth"), do: {:next_state, "wait_login_to_finish_registration"}
    def forward(_, "twitter_oauth"), do: {:next_state, "wait_login_to_finish_registration"}
    def forward(_, "eth_login"), do: {:next_state, "finished"}
    def forward(_, "email_login_verify"), do: {:next_state, "finished"}
    def forward("wait_login_to_finish_registration", "login"), do: {:next_state, "finished"}
  end
end
