defmodule Sippet.Transaction.Server.NonInvite do
  use Sippet.Transaction.Server, initial_state: :trying

  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transaction.Server.State, as: State

  @max_idle 4000
  @timer_j 32000

  def trying(:enter, _old_state, %State{request: request} = data) do
    receive_request(request, data)
    {:keep_state_and_data, [{:state_timeout, @max_idle, nil}]}
  end

  def trying(:state_timeout, _nil, data),
    do: shutdown(:idle, data)

  def trying(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def trying(:cast, {:outgoing_response, response}, data) do
    data = send_response(response, data)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:next_state, :proceeding, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def trying(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def trying(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def proceeding(:enter, _old_state, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:incoming_request, _request},
      %State{extras: %{last_response: last_response}} = data) do
    send_response(last_response, data)
    :keep_state_and_data
  end

  def proceeding(:cast, {:outgoing_response, response}, data) do
    data = send_response(response, data)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def proceeding(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def completed(:enter, _old_state, %State{request: request} = data) do
    if reliable?(request) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_j, nil}]}
    end
  end

  def completed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def completed(:cast, {:incoming_request, _request},
      %State{extras: %{last_response: last_response}} = data) do
    send_response(last_response, data)
    :keep_state_and_data
  end

  def completed(:cast, {:error, _reason}, _data),
    do: :keep_state_and_data

  def completed(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end
