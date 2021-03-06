defmodule Kaffe.Worker do
  @moduledoc """

  A worker receives messages for a single topic partition.

  Processing the message set is delegated to the configured message
  handler. It is responsible for any error handling. The message handler
  must define a `init_handler/0` function that should return `{:ok, state}`, and
  a `handle_messages` function (*note* the pluralization!)
  to accept a list of messages and a state, and returns `{:ok, state}`.

  The result of `handle_messages` is sent back to the subscriber.
  """

  require Logger

  def start_link(message_handler, subscriber_name, worker_name) do
    GenServer.start_link(__MODULE__, [message_handler, worker_name],
        name: name(subscriber_name, worker_name))
  end

  def init([message_handler, worker_name]) do
    Logger.info "event#starting=#{__MODULE__} name=#{worker_name}"
    {:ok, handler_state } = apply(message_handler, :init_handler, [])
    {:ok, %{message_handler: message_handler, worker_name: worker_name, handler_state: handler_state}}
  end

  def process_messages(pid, subscriber_pid, topic, partition, generation_id, messages) do
    GenServer.cast(pid, {:process_messages, subscriber_pid, topic, partition, generation_id, messages})
  end

  def handle_cast({:process_messages, subscriber_pid, topic, partition, generation_id, messages},
      %{message_handler: message_handler, handler_state: handler_state} = state) do

    new_handler_state_2 = case apply(message_handler, :handle_messages, [messages, handler_state]) do
      {:ok, new_handler_state}->
        subscriber().ack_messages(subscriber_pid, topic, partition, generation_id, List.last(messages).offset)
        new_handler_state
      {:ok, new_handler_state, :no_ack} ->
        subscriber().ack_messages(subscriber_pid, topic, partition, generation_id, List.last(messages).offset, false)
        new_handler_state
      {:ok, new_handler_state, offset} ->
        subscriber().ack_messages(subscriber_pid, topic, partition, generation_id, offset)
        new_handler_state
    end

    {:noreply, %{state| handler_state: new_handler_state_2}}
  end

  def terminate(reason, _state) do
    Logger.info "event#terminate=#{inspect self()} reason=#{inspect reason}"
  end

  defp name(subscriber_name, worker_name) do
    :"kaffe_#{subscriber_name}_#{worker_name}"
  end

  defp subscriber do
    Application.get_env(:kaffe, :subscriber_mod, Kaffe.Subscriber)
  end

end
