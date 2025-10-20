defmodule FinancialAdvisorAiWeb.WebhookController do
  @moduledoc """
  Handles webhook notifications from Google (Gmail, Calendar) and HubSpot.
  Enables proactive agent behavior by responding to external events.
  """

  use FinancialAdvisorAiWeb, :controller
  require Logger

  alias FinancialAdvisorAi.Workers.{EmailSyncWorker, ContactSyncWorker}

  # ============================================================================
  # GMAIL WEBHOOKS (Gmail Push Notifications)
  # ============================================================================

  @doc """
  Handle Gmail push notifications.

  Gmail sends webhooks when new emails arrive or labels change.
  """
  def gmail_webhook(conn, params) do
    Logger.info("Received Gmail webhook: #{inspect(params)}")

    # Gmail sends the message in the request body
    message = params["message"]

    if message do
      # Decode the base64 data
      data = message["data"] |> Base.decode64!(padding: false) |> Jason.decode!()

      user_email = data["emailAddress"]
      history_id = data["historyId"]

      Logger.info("Gmail notification for #{user_email}, historyId: #{history_id}")

      # Find user by email and trigger sync
      case find_user_by_google_email(user_email) do
        {:ok, user} ->
          # Enqueue email sync job
          EmailSyncWorker.enqueue_sync(user.id, days_back: 1)

          conn
          |> put_status(:ok)
          |> json(%{status: "ok", action: "sync_queued"})

        {:error, :not_found} ->
          Logger.warning("No user found for email #{user_email}")

          conn
          |> put_status(:ok)
          |> json(%{status: "ok", action: "user_not_found"})
      end
    else
      conn
      |> put_status(:ok)
      |> json(%{status: "ok", action: "ignored"})
    end
  end

  # ============================================================================
  # CALENDAR WEBHOOKS
  # ============================================================================

  @doc """
  Handle Google Calendar push notifications.

  Calendar sends webhooks when events are created, updated, or deleted.
  """
  def calendar_webhook(conn, params) do
    Logger.info("Received Calendar webhook: #{inspect(params)}")

    # Get headers
    resource_id = get_req_header(conn, "x-goog-resource-id") |> List.first()
    resource_state = get_req_header(conn, "x-goog-resource-state") |> List.first()
    channel_id = get_req_header(conn, "x-goog-channel-id") |> List.first()

    Logger.info("Calendar notification: resource_id=#{resource_id}, state=#{resource_state}, channel=#{channel_id}")

    # Extract user_id from channel_id (we encode it when setting up the watch)
    case extract_user_id_from_channel(channel_id) do
      {:ok, user_id} ->
        # Could trigger specific actions based on resource_state:
        # - "sync" = initial sync
        # - "exists" = resource exists
        # - "not_exists" = resource deleted

        # For now, just log it
        Logger.info("Calendar event changed for user #{user_id}")

        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", action: "ignored"})
    end
  end

  # ============================================================================
  # HUBSPOT WEBHOOKS
  # ============================================================================

  @doc """
  Handle HubSpot webhooks.

  HubSpot sends webhooks for:
  - contact.creation
  - contact.propertyChange
  - deal.creation
  - deal.propertyChange
  - etc.
  """
  def hubspot_webhook(conn, params) do
    Logger.info("Received HubSpot webhook: #{inspect(params)}")

    # HubSpot sends an array of events
    events = params[:events] || params["events"] || []

    Enum.each(events, fn event ->
      handle_hubspot_event(event)
    end)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  @doc """
  Verify HubSpot webhook signature.
  This should be called before processing webhook to ensure it's from HubSpot.
  """
  def verify_hubspot_signature(conn, _opts \\ []) do
    # Get signature from header
    signature = get_req_header(conn, "x-hubspot-signature") |> List.first()

    # In production, verify the signature
    # For now, just pass through
    # TODO: Implement signature verification

    conn
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp handle_hubspot_event(event) do
    event_type = event["subscriptionType"]
    object_id = event["objectId"]
    portal_id = event["portalId"]

    Logger.info("HubSpot event: #{event_type} for object #{object_id} in portal #{portal_id}")

    case event_type do
      "contact.creation" ->
        # New contact created - trigger sync
        trigger_contact_sync_for_portal(portal_id)

      "contact.propertyChange" ->
        # Contact updated - could trigger re-embedding
        trigger_contact_sync_for_portal(portal_id)

      "deal.creation" ->
        # New deal created - could notify user
        Logger.info("New deal created: #{object_id}")

      _ ->
        Logger.debug("Unhandled HubSpot event type: #{event_type}")
    end
  end

  defp trigger_contact_sync_for_portal(portal_id) do
    # Find user by HubSpot portal ID and trigger contact sync
    case find_user_by_hubspot_portal(portal_id) do
      {:ok, user} ->
        ContactSyncWorker.enqueue_sync(user.id)

      {:error, :not_found} ->
        Logger.warning("No user found for HubSpot portal #{portal_id}")
    end
  end

  defp find_user_by_google_email(email) do
    # This is a simplified lookup - in production you'd store the watched email
    case FinancialAdvisorAi.Repo.get_by(FinancialAdvisorAi.Accounts.User, email: email) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp find_user_by_hubspot_portal(portal_id) do
    # In production, you'd store the portal_id in the user record
    # For now, this is a placeholder
    {:error, :not_found}
  end

  defp extract_user_id_from_channel(channel_id) when is_binary(channel_id) do
    # Channel ID format: "calendar_watch_USER_ID"
    case String.split(channel_id, "_") do
      ["calendar", "watch", user_id] -> {:ok, user_id}
      _ -> {:error, :invalid_format}
    end
  end
  defp extract_user_id_from_channel(_), do: {:error, :invalid_format}
end
