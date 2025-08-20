defmodule HelloElixir.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :io.format(">>>>> ~s~n", [Hello.world()])

    children = []
    opts = [strategy: :one_for_one, name: HelloElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
