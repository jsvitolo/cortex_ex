defmodule CortexEx.Auth do
  @moduledoc """
  OAuth 2.1 resource-server support: config, JWT verification (RS256 via
  JWKS), and RFC 9728 protected resource metadata.

  Auth is enabled by configuring the host app:

      config :cortex_ex, CortexEx.Auth,
        issuer: "https://your-tenant.authkit.app",
        audience: "https://app.example.com/cortex_ex/mcp",
        allowed_domain: "example.com"

  Without this config the MCP endpoint is open (dev mode) and a warning is
  logged at boot.
  """

  alias CortexEx.Auth.JwksCache
  alias CortexEx.Identity

  @required_keys [:issuer, :audience, :allowed_domain]
  @leeway_seconds 60

  @spec config() :: map() | nil
  def config do
    case Application.get_env(:cortex_ex, __MODULE__) do
      nil -> nil
      opts -> normalize(opts)
    end
  end

  @spec enabled?() :: boolean()
  def enabled?, do: config() != nil

  @doc "Raises at boot when auth config is present but incomplete."
  @spec validate_config!() :: :ok
  def validate_config! do
    case Application.get_env(:cortex_ex, __MODULE__) do
      nil ->
        :ok

      opts ->
        missing = Enum.filter(@required_keys, &(Keyword.get(opts, &1) in [nil, ""]))

        if missing != [] do
          raise ArgumentError,
                "incomplete config for :cortex_ex, CortexEx.Auth — missing #{inspect(missing)}. " <>
                  "Auth is all-or-nothing: provide issuer, audience and allowed_domain, " <>
                  "or remove the config entirely to run unauthenticated (dev only)."
        end

        :ok
    end
  end

  @doc """
  Verifies a bearer token: RS256 signature against the JWKS, exp/nbf/iss/aud
  claims, then email/domain rules. Fail closed on any doubt.
  """
  @spec verify_token(String.t()) :: {:ok, Identity.t()} | {:error, atom()}
  def verify_token(token) do
    config = config() || raise "CortexEx.Auth.verify_token/1 called with auth disabled"

    with {:ok, %{"alg" => "RS256"} = header} <- peek_header(token),
         {:ok, jwk} <- JwksCache.get_key(header["kid"]),
         {:ok, claims} <- verify_signature(token, jwk),
         :ok <- check_time_claims(claims),
         :ok <- check_issuer(claims, config),
         :ok <- check_audience(claims, config),
         {:ok, identity} <- Identity.from_claims(claims, config) do
      {:ok, identity}
    else
      {:ok, %{}} -> {:error, :invalid_algorithm}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "RFC 9728 protected resource metadata document."
  @spec resource_metadata() :: map()
  def resource_metadata do
    config = config()

    %{
      resource: config.resource,
      authorization_servers: [config.issuer],
      bearer_methods_supported: ["header"]
    }
  end

  @doc "Absolute URL of the protected resource metadata document."
  @spec resource_metadata_url() :: String.t()
  def resource_metadata_url do
    uri = URI.parse(config().resource)
    origin = %URI{scheme: uri.scheme, host: uri.host, port: uri.port} |> URI.to_string()
    origin <> "/.well-known/oauth-protected-resource" <> uri.path
  end

  @doc """
  Path segments (as `conn.path_info`) where the metadata document is served,
  e.g. `[".well-known", "oauth-protected-resource", "cortex_ex", "mcp"]`.
  """
  @spec metadata_path_info() :: [String.t()]
  def metadata_path_info do
    path = URI.parse(config().resource).path || ""
    [".well-known", "oauth-protected-resource" | String.split(path, "/", trim: true)]
  end

  defp normalize(opts) do
    audience = Keyword.fetch!(opts, :audience)

    %{
      issuer: Keyword.fetch!(opts, :issuer) |> String.trim_trailing("/"),
      audience: audience,
      allowed_domain: Keyword.fetch!(opts, :allowed_domain),
      resource: Keyword.get(opts, :resource, audience),
      jwks_uri: Keyword.get(opts, :jwks_uri),
      email_claim: Keyword.get(opts, :email_claim, "email"),
      jwks_ttl_seconds: Keyword.get(opts, :jwks_ttl_seconds, 600),
      jwks_fetcher: Keyword.get(opts, :jwks_fetcher)
    }
  end

  defp peek_header(token) do
    case Joken.peek_header(token) do
      {:ok, header} -> {:ok, header}
      {:error, _} -> {:error, :malformed_token}
    end
  rescue
    _ -> {:error, :malformed_token}
  end

  defp verify_signature(token, jwk_map) do
    signer = Joken.Signer.create("RS256", jwk_map)

    case Joken.verify(token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, _} -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp check_time_claims(claims) do
    now = System.system_time(:second)

    cond do
      not is_integer(claims["exp"]) -> {:error, :missing_exp}
      claims["exp"] + @leeway_seconds <= now -> {:error, :token_expired}
      is_integer(claims["nbf"]) and claims["nbf"] - @leeway_seconds > now -> {:error, :token_not_yet_valid}
      true -> :ok
    end
  end

  defp check_issuer(%{"iss" => iss}, config) when is_binary(iss) do
    if String.trim_trailing(iss, "/") == config.issuer, do: :ok, else: {:error, :invalid_issuer}
  end

  defp check_issuer(_, _), do: {:error, :invalid_issuer}

  defp check_audience(%{"aud" => aud}, config) do
    audiences = List.wrap(aud)
    if config.audience in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp check_audience(_, _), do: {:error, :invalid_audience}
end
