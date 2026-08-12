defmodule CortexEx.Identity do
  @moduledoc """
  Verified identity of an MCP caller, built from validated JWT claims.

  `nil` identity means auth is disabled (open/dev mode).
  """

  @enforce_keys [:sub, :email, :domain]
  defstruct [:sub, :email, :domain, claims: %{}]

  @type t :: %__MODULE__{
          sub: String.t(),
          email: String.t(),
          domain: String.t(),
          claims: map()
        }

  @doc """
  Builds an identity from verified claims, enforcing email and domain rules.

  Rules:
    * the configured email claim must be present and look like an email
    * `email_verified`, when present, must be true
    * the email domain must equal the configured `allowed_domain`
    * `hd`, when present, must also equal `allowed_domain`
  """
  @spec from_claims(map(), map()) :: {:ok, t()} | {:error, atom()}
  def from_claims(claims, config) do
    email_claim = config[:email_claim] || "email"

    with {:ok, email} <- fetch_email(claims, email_claim),
         :ok <- check_email_verified(claims),
         {:ok, domain} <- check_domain(email, config.allowed_domain),
         :ok <- check_hd(claims, config.allowed_domain) do
      {:ok,
       %__MODULE__{
         sub: to_string(claims["sub"] || email),
         email: email,
         domain: domain,
         claims: claims
       }}
    end
  end

  defp fetch_email(claims, email_claim) do
    case claims[email_claim] do
      email when is_binary(email) and email != "" ->
        email = String.downcase(email)
        if String.contains?(email, "@"), do: {:ok, email}, else: {:error, :invalid_email}

      _ ->
        {:error, :missing_email}
    end
  end

  defp check_email_verified(%{"email_verified" => verified}) when verified not in [true, "true"],
    do: {:error, :email_not_verified}

  defp check_email_verified(_), do: :ok

  defp check_domain(email, allowed_domain) do
    domain = email |> String.split("@") |> List.last()

    if domain == String.downcase(allowed_domain) do
      {:ok, domain}
    else
      {:error, :domain_not_allowed}
    end
  end

  defp check_hd(%{"hd" => hd}, allowed_domain) when is_binary(hd) do
    if String.downcase(hd) == String.downcase(allowed_domain),
      do: :ok,
      else: {:error, :domain_not_allowed}
  end

  defp check_hd(_, _), do: :ok
end
