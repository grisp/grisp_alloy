defmodule Hello do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    case :code.priv_dir(:hello_elixir) do
      dir when is_list(dir) ->
        path = :filename.join(dir, ~c"hello")
        case :erlang.load_nif(path, 0) do
          :ok -> :ok
          {:error, _} -> :ok
        end

      _ ->
        :ok
    end
  end

  def world, do: :erlang.nif_error(:nif_not_loaded)
end
