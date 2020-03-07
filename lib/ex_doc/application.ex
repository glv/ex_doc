defmodule ExDoc.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    ExDoc.Refs.start()
    Supervisor.start_link([], strategy: :one_for_one)
  end
end
