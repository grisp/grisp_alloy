defmodule HelloElixir.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :io.format(">>>>> ~s~n", [Hello.world()])
    :io.format("Config: ~p~n", [Application.get_env(:hello_elixir, :key)])
    children = []
    opts = [strategy: :one_for_one, name: HelloElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
