defmodule FinancialAdvisorAiWeb.AuthController do
  @moduledoc """
  Handles OAuth authentication for Google and HubSpot.
  """

  use FinancialAdvisorAiWeb, :controller
  plug Ueberauth

  alias FinancialAdvisorAi.Accounts
  alias FinancialAdvisorAi.Accounts.User

  require Logger

  # ============================================================================
  # GOOGLE OAUTH
  # ============================================================================

  @doc """
  Callback from Google OAuth.
  Creates or updates user with Google credentials.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => "google"}) do
    user_params = %{
      email: auth.info.email,
      name: auth.info.name,
      google_id: auth.uid,
      google_access_token: auth.credentials.token,
      google_refresh_token: auth.credentials.refresh_token,
      google_token_expires_at: expires_at_from_timestamp(auth.credentials.expires_at)
    }

    case Accounts.upsert_user_by_google_id(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated with Google!")
        |> redirect(to: "/chat")

      {:error, reason} ->
        Logger.error("Failed to create/update user: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: "/")
    end
  end

  @doc """
  Handle authentication failures from Ueberauth.
  """
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, %{"provider" => "google"}) do
    conn
    |> put_flash(:error, "Failed to authenticate with Google.")
    |> redirect(to: "/")
  end

  # ============================================================================
  # HUBSPOT OAUTH
  # ============================================================================

  @doc """
  Initiate HubSpot OAuth flow.
  Redirects user to HubSpot authorization page.
  """
  def hubspot_authorize(conn, _params) do
    client_id = Application.get_env(:financial_advisor_ai, :hubspot_client_id)
    redirect_uri = Application.get_env(:financial_advisor_ai, :hubspot_redirect_uri)

    scopes = [
      "crm.objects.contacts.read",
      "crm.objects.contacts.write",
      "oauth"
    ]

    scope_string = Enum.join(scopes, " ")

    authorize_url = "https://app.hubspot.com/oauth/authorize?" <>
      "client_id=#{client_id}" <>
      "&redirect_uri=#{URI.encode_www_form(redirect_uri)}" <>
      "&scope=#{URI.encode_www_form(scope_string)}"

    redirect(conn, external: authorize_url)
  end

  @doc """
  HubSpot OAuth callback.
  Exchanges code for access token and saves to user.
  """
  def callback(conn, %{"code" => code, "provider" => "hubspot"}) do
    user_id = get_session(conn, :user_id)

    if !user_id do
      conn
      |> put_flash(:error, "Please sign in with Google first.")
      |> redirect(to: "/")
    else
      case exchange_hubspot_code(code) do
        {:ok, token_data} ->
          user_params = %{
            hubspot_access_token: token_data["access_token"],
            hubspot_refresh_token: token_data["refresh_token"],
            hubspot_token_expires_at: expires_at_from_seconds(token_data["expires_in"])
          }

          case Accounts.update_user_tokens(user_id, user_params) do
            {:ok, _user} ->
              conn
              |> put_flash(:info, "Successfully connected to HubSpot!")
              |> redirect(to: "/chat")

            {:error, reason} ->
              Logger.error("Failed to save HubSpot tokens: #{inspect(reason)}")
              conn
              |> put_flash(:error, "Failed to save HubSpot connection.")
              |> redirect(to: "/chat")
          end

        {:error, reason} ->
          Logger.error("HubSpot token exchange failed: #{inspect(reason)}")
          conn
          |> put_flash(:error, "HubSpot authorization failed.")
          |> redirect(to: "/chat")
      end
    end
  end

  @doc """
  Handle authentication failures from Ueberauth.
  """
  def callback(conn, %{"error" => error, "provider" => "hubspot"}) do
    Logger.error("HubSpot OAuth error: #{error}")
    conn
    |> put_flash(:error, "HubSpot authorization was denied.")
    |> redirect(to: "/chat")
  end

  # ============================================================================
  # LOGOUT
  # ============================================================================

  @doc """
  Sign out the current user.
  """
  def signout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Successfully signed out.")
    |> redirect(to: "/")
  end

  # ============================================================================
  # TOKEN REFRESH
  # ============================================================================

  @doc """
  Refresh Google access token using refresh token.
  """
  def refresh_google_token(%User{} = user) do
    if !user.google_refresh_token do
      {:error, "No refresh token available"}
    else
      client_id = Application.get_env(:financial_advisor_ai, :google_client_id)
      client_secret = Application.get_env(:financial_advisor_ai, :google_client_secret)

      body = %{
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: user.google_refresh_token,
        grant_type: "refresh_token"
      }

      case Req.post("https://oauth2.googleapis.com/token", json: body) do
        {:ok, %{status: 200, body: response}} ->
          new_params = %{
            google_access_token: response["access_token"],
            google_token_expires_at: expires_at_from_seconds(response["expires_in"])
          }

          Accounts.update_user_tokens(user.id, new_params)

        {:ok, %{status: status, body: body}} ->
          Logger.error("Google token refresh failed: #{status} - #{inspect(body)}")
          {:error, "Token refresh failed"}

        {:error, reason} ->
          Logger.error("Google token refresh request failed: #{inspect(reason)}")
          {:error, "Token refresh request failed"}
      end
    end
  end

  @doc """
  Refresh HubSpot access token using refresh token.
  """
  def refresh_hubspot_token(%User{} = user) do
    if !user.hubspot_refresh_token do
      {:error, "No refresh token available"}
    else
      client_id = Application.get_env(:financial_advisor_ai, :hubspot_client_id)
      client_secret = Application.get_env(:financial_advisor_ai, :hubspot_client_secret)

      body = %{
        grant_type: "refresh_token",
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: user.hubspot_refresh_token
      }

      case Req.post("https://api.hubapi.com/oauth/v1/token", form: body) do
        {:ok, %{status: 200, body: response}} ->
          new_params = %{
            hubspot_access_token: response["access_token"],
            hubspot_refresh_token: response["refresh_token"],
            hubspot_token_expires_at: expires_at_from_seconds(response["expires_in"])
          }

          Accounts.update_user_tokens(user.id, new_params)

        {:ok, %{status: status, body: body}} ->
          Logger.error("HubSpot token refresh failed: #{status} - #{inspect(body)}")
          {:error, "Token refresh failed"}

        {:error, reason} ->
          Logger.error("HubSpot token refresh request failed: #{inspect(reason)}")
          {:error, "Token refresh request failed"}
      end
    end
  end

  @doc """
  Ensure user has valid Google token, refreshing if necessary.
  """
  def ensure_google_token(%User{} = user) do
    if User.google_token_expired?(user) do
      refresh_google_token(user)
    else
      {:ok, user}
    end
  end

  @doc """
  Ensure user has valid HubSpot token, refreshing if necessary.
  """
  def ensure_hubspot_token(%User{} = user) do
    if User.hubspot_token_expired?(user) do
      refresh_hubspot_token(user)
    else
      {:ok, user}
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp exchange_hubspot_code(code) do
    client_id = Application.get_env(:financial_advisor_ai, :hubspot_client_id)
    client_secret = Application.get_env(:financial_advisor_ai, :hubspot_client_secret)
    redirect_uri = Application.get_env(:financial_advisor_ai, :hubspot_redirect_uri)

    body = %{
      grant_type: "authorization_code",
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      code: code
    }

    case Req.post("https://api.hubapi.com/oauth/v1/token", form: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "Status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expires_at_from_timestamp(nil), do: nil
  defp expires_at_from_timestamp(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  defp expires_at_from_seconds(nil), do: nil
  defp expires_at_from_seconds(seconds) when is_integer(seconds) do
    DateTime.utc_now() |> DateTime.add(seconds, :second)
  end
end
