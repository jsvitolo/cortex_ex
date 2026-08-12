defmodule CortexEx.AuthCase do
  @moduledoc """
  Helpers for auth tests: RSA keypair generation, token signing, and auth
  config injection with a static JWKS fetcher (no HTTP).
  """

  @kid "test-kid"

  @issuer "https://auth.test"
  @audience "https://app.test/cortex_ex/mcp"
  @domain "empresa.com"

  def issuer, do: @issuer
  def audience, do: @audience
  def domain, do: @domain

  def generate_jwk, do: JOSE.JWK.generate_key({:rsa, 2048})

  def public_jwks(jwk) do
    {_meta, public_map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{"keys" => [Map.put(public_map, "kid", @kid)]}
  end

  def sign_token(jwk, claims, opts \\ []) do
    kid = Keyword.get(opts, :kid, @kid)
    alg = Keyword.get(opts, :alg, "RS256")

    {_meta, token} = jwk |> JOSE.JWT.sign(%{"alg" => alg, "kid" => kid}, claims) |> JOSE.JWS.compact()
    token
  end

  def hs256_token(claims, opts \\ []) do
    kid = Keyword.get(opts, :kid, @kid)
    jwk = JOSE.JWK.from_oct("super-secret-hmac-key-for-tests!")

    {_meta, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256", "kid" => kid}, claims) |> JOSE.JWS.compact()
    token
  end

  def default_claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => @issuer,
        "aud" => @audience,
        "sub" => "user_123",
        "email" => "dev@#{@domain}",
        "exp" => now + 3600,
        "iat" => now
      },
      overrides
    )
  end

  @doc "Enables auth with a static JWKS and registers cleanup on exit."
  def put_auth_config(jwks, overrides \\ []) do
    config =
      Keyword.merge(
        [
          issuer: @issuer,
          audience: @audience,
          allowed_domain: @domain,
          jwks_uri: "#{@issuer}/jwks",
          jwks_fetcher: fn _url -> {:ok, jwks} end
        ],
        overrides
      )

    Application.put_env(:cortex_ex, CortexEx.Auth, config)
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:cortex_ex, CortexEx.Auth) end)
    :ok
  end

  def identity(email \\ "dev@#{@domain}") do
    %CortexEx.Identity{sub: "user_123", email: email, domain: @domain}
  end
end
