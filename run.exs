Mix.install([
  # {:phoenix_playground, path: "../phoenix_playground"},
  {:phoenix_playground, github: "ringvold/phoenix_playground", branch: "fly-ready"},
  :jason
])

defmodule Consultant do
  def file(path) do
    with {:ok, data} <- File.read(path), do: string(data)
  end

  def string(input) do
    with {:ok, quoted} <- Code.string_to_quoted(input), do: {:ok, parse(wrap(quoted))}
  catch
    {:error, _} = error -> error
  end

  defp wrap({:__block__, _, data}), do: data
  defp wrap(data), do: [data]

  defp parse(data) when is_number(data) when is_binary(data) when is_atom(data),
    do: data

  defp parse(list) when is_list(list) do
    Enum.map(list, fn
      {k, v} -> {parse(k), parse(v)}
      other -> parse(other)
    end)
  end

  defp parse({:%{}, _, data}) do
    for {key, value} <- data, into: %{}, do: {parse(key), parse(value)}
  end

  defp parse({:{}, _, data}) do
    data
    |> Enum.map(&parse/1)
    |> List.to_tuple()
  end

  defp parse({:__aliases__, _, names}), do: Module.concat(names)

  defp parse({:sigil_W, _meta, [{:<<>>, _, [string]}, mod]}), do: word_sigil(string, mod)

  defp parse({:sigil_R, _meta, [{:<<>>, _, [string]}, mod]}),
    do: Regex.compile!(string, List.to_string(mod))

  defp parse({sigil, meta, _data} = quoted) when sigil in ~w[sigil_w sigil_r]a do
    line = Keyword.get(meta, :line)
    throw({:error, {:illegal_sigil, line, quoted}})
  end

  defp parse({_, meta, _} = quoted) do
    line = Keyword.get(meta, :line)
    throw({:error, {:invalid, line, quoted}})
  end

  defp word_sigil(string, []), do: word_sigil(string, ~c"s")

  defp word_sigil(string, [mod]) when mod in ~c"sac" do
    parts = String.split(string)

    case mod do
      ?s -> parts
      ?a -> Enum.map(parts, &String.to_atom/1)
      ?c -> Enum.map(parts, &String.to_charlist/1)
    end
  end

  defp parse(data), do: data
end

defmodule JsonToElixirLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    initial = ~S|{"foo": "bar"}|
    {:ok, assign(socket, transformed: Jason.decode!(initial), json: initial)}
  end

  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com"></script>
    <div class="mx-auto p-10">
      <h1 class="text-3xl font-bold mb-10">JSON to Elixir map</h1>
      <div class="flex flex-row flex-1 space-x-10" >
        <form class="flex-1" phx-change="change_json">
          <label for="json" class="my-4 text-2xl font-bold">JSON</label>
          <textarea id="json" name="json" class="my-5 p-3 w-full h-96 rounded border border-zinc-500"><%= @json %></textarea>
        </form>
        <form class="flex-1" phx-change="change_map">
          <label for="map" class="my-4 text-2xl font-bold">Elixir map</label>
          <textarea id="map" name="map" class="my-5 p-3 w-full h-96 rounded border border-zinc-500"><%= inspect(@transformed, structs: false, pretty: true) %></textarea>
        </form>
      </div>
    </div>
    """
  end

  def handle_event("change_json", %{"json" => json} = params, socket) do
    case Jason.decode(json) do
      {:ok, map} ->
        {:noreply, assign(socket, transformed: map)}

      {:error, _err} ->
        # TODO: Display errors
        {:noreply, assign(socket, transformed: socket.assigns.transformed)}
    end
  end

  def handle_event("change_map", %{"map" => map} = params, socket) do
    case Consultant.string(map) do
      {:ok, [json | _]} ->
        {:noreply, assign(socket, json: Jason.encode!(json))}

      {:error, err} ->
        # dbg(err)
        # TODO: Display errors
        {:noreply, assign(socket, json: socket.assigns.json)}
    end
  end

  def handle_event("change", _params, socket) do
    {:noreply, socket}
  end
end

host =
  if app = System.get_env("FLY_APP_NAME") do
    app <> ".fly.dev"
  else
    "localhost"
  end

port = String.to_integer(System.get_env("PORT") || "4000")

# Dry run for copying cached mix install from builder to runner
if System.get_env("EXS_DRY_RUN") == "true" do
  System.halt(0)
else
  if System.get_env("MIX_ENV") == "prod" do
    PhoenixPlayground.start(
      live: JsonToElixirLive,
      host: host,
      port: port,
      ip: :any,
      open_browser: false,
      live_reload: false
    )
  else
    PhoenixPlayground.start(live: JsonToElixirLive)
  end
end


