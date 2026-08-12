defmodule CortexEx.Auth.JwksCache do
  @moduledoc """
  Caches the authorization server's JWKS. Lazy fetch on first use, TTL
  refresh, and a rate-limited forced refresh when an unknown `kid` shows up
  (key rotation). Fails closed: unreachable JWKS means verification fails.
  """

  use GenServer
  require Logger

  @forced_refresh_interval_ms 30_000
  @http_timeout_ms 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec get_key(String.t() | nil) :: {:ok, map()} | {:error, :unknown_kid | :unavailable}
  def get_key(kid) do
    GenServer.call(__MODULE__, {:get_key, kid}, @http_timeout_ms * 2)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl true
  def init(_opts) do
    {:ok, %{keys: %{}, jwks_uri: nil, fetched_at: nil, last_forced_refresh: nil}}
  end

  @impl true
  def handle_call({:get_key, kid}, _from, state) do
    state = maybe_refresh(state)

    case Map.fetch(state.keys, kid) do
      {:ok, jwk} ->
        {:reply, {:ok, jwk}, state}

      :error ->
        # Unknown kid may mean key rotation — force one refresh, rate-limited.
        state = maybe_force_refresh(state)

        case Map.fetch(state.keys, kid) do
          {:ok, jwk} -> {:reply, {:ok, jwk}, state}
          :error when state.keys == %{} -> {:reply, {:error, :unavailable}, state}
          :error -> {:reply, {:error, :unknown_kid}, state}
        end
    end
  end

  defp maybe_refresh(state) do
    ttl_ms = (CortexEx.Auth.config()[:jwks_ttl_seconds] || 600) * 1000
    now = System.monotonic_time(:millisecond)

    if state.fetched_at == nil or now - state.fetched_at > ttl_ms do
      refresh(state)
    else
      state
    end
  end

  defp maybe_force_refresh(state) do
    now = System.monotonic_time(:millisecond)

    if state.last_forced_refresh == nil or
         now - state.last_forced_refresh > @forced_refresh_interval_ms do
      refresh(%{state | last_forced_refresh: now})
    else
      state
    end
  end

  defp refresh(state) do
    config = CortexEx.Auth.config()

    with {:ok, uri, state} <- resolve_jwks_uri(state, config),
         {:ok, body} <- fetch(uri, config) do
      keys =
        for key <- body["keys"] || [], is_binary(key["kid"]), into: %{} do
          {key["kid"], key}
        end

      %{state | keys: keys, fetched_at: System.monotonic_time(:millisecond)}
    else
      {:error, reason} ->
        Logger.warning("CortexEx.Auth: JWKS refresh failed: #{inspect(reason)}")
        state
    end
  end

  defp resolve_jwks_uri(%{jwks_uri: uri} = state, _config) when is_binary(uri),
    do: {:ok, uri, state}

  defp resolve_jwks_uri(state, %{jwks_uri: uri}) when is_binary(uri),
    do: {:ok, uri, %{state | jwks_uri: uri}}

  defp resolve_jwks_uri(state, config) do
    discovery_paths = [
      config.issuer <> "/.well-known/oauth-authorization-server",
      config.issuer <> "/.well-known/openid-configuration"
    ]

    Enum.reduce_while(discovery_paths, {:error, :discovery_failed}, fn url, acc ->
      case fetch(url, config) do
        {:ok, %{"jwks_uri" => jwks_uri}} when is_binary(jwks_uri) ->
          {:halt, {:ok, jwks_uri, %{state | jwks_uri: jwks_uri}}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp fetch(url, config) do
    case config[:jwks_fetcher] do
      fetcher when is_function(fetcher, 1) -> fetcher.(url)
      {mod, fun} -> apply(mod, fun, [url])
      nil -> http_get(url)
    end
  end

  defp http_get(url) do
    request = {String.to_charlist(url), [{~c"accept", ~c"application/json"}]}

    http_opts = [
      timeout: @http_timeout_ms,
      connect_timeout: @http_timeout_ms,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> Jason.decode(body)
      {:ok, {{_, status, _}, _, _}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
