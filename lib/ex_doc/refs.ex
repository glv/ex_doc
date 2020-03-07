defmodule ExDoc.Refs do
  @moduledoc false

  @type ref() :: {:module, module()} | {kind :: atom(), name :: atom(), arity}

  @name __MODULE__

  @spec start() :: :ok
  def start() do
    :ets.new(@name, [:named_table, :public, :set])
    :ok
  end

  @spec clear() :: :ok
  def clear() do
    :ets.delete_all_objects(@name)
    :ok
  end

  @spec public?(ref()) :: boolean()
  def public?(ref) do
    case :ets.lookup(@name, ref) do
      [{^ref, true}] ->
        true

      [{^ref, false}] ->
        false

      [] ->
        case load(ref) do
          # when we only have exports, consider all types and callbacks refs as matching
          {:exports, entries} when elem(ref, 0) in [:type, :callback] ->
            :ok = insert([{ref, true} | entries])
            true

          {_, entries} ->
            :ok = insert(entries)
            {ref, true} in entries
        end
    end
  end

  @spec insert([{ref, boolean}]) :: :ok
  def insert(entries) do
    true = :ets.insert(@name, entries)
    :ok
  end

  # Returns refs for `module` from the result of calling `Code.fetch_docs/1`.
  @doc false
  def from_chunk(module, result) do
    case result do
      {:docs_v1, _, _, _, :hidden, _, _} ->
        {:chunk, [{{:module, module}, false}]}

      {:docs_v1, _, _, _, _, _, docs} ->
        entries =
          for {{kind, name, arity}, _, _, doc, metadata} <- docs do
            tag = doc != :hidden

            for arity <- (arity - (metadata[:defaults] || 0))..arity do
              {{kind(kind), module, name, arity}, tag}
            end
          end

        entries = [{{:module, module}, true} | List.flatten(entries)]
        {:chunk, entries}

      {:error, :chunk_not_found} ->
        entries =
          for {name, arity} <- exports(module) do
            {{:function, module, name, arity}, true}
          end

        entries = [{{:module, module}, true} | entries]
        {:exports, entries}

      _ ->
        entries = [{{:module, module}, false}]
        {:none, entries}
    end
  end

  defp exports(module) do
    if function_exported?(module, :__info__, 1) do
      module.__info__(:functions) ++ module.__info__(:macros)
    else
      module.module_info(:exports)
    end
  end

  defp load({:module, module}) do
    from_chunk(module, ExDoc.Utils.Code.fetch_docs(module))
  end

  defp load({_kind, module, _name, _arity}) do
    load({:module, module})
  end

  defp kind(:macro), do: :function
  defp kind(:macrocallback), do: :callback
  defp kind(other), do: other
end
