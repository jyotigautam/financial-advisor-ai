defmodule FinancialAdvisorAiWeb.ChatLive do
  use FinancialAdvisorAiWeb, :live_view
  alias FinancialAdvisorAi.{Accounts, Chat, DataSync}
  alias FinancialAdvisorAi.AI.Agent

  @impl true
  def mount(params, session, socket) do
    require Logger

    # Debug: Log session info
    Logger.info("ChatLive mount - session user_id: #{inspect(session["user_id"])}")

    # Get user from session (set during OAuth) or fallback to demo user
    user = case session["user_id"] do
      nil ->
        Logger.info("No user_id in session, using demo user")
        # No authenticated user, use demo user
        Accounts.get_or_create_demo_user()
      user_id ->
        Logger.info("Found user_id in session: #{user_id}")
        # Load authenticated user from session
        case Accounts.get_user(user_id) do
          nil ->
            Logger.warning("User #{user_id} not found in database, using demo user")
            # User not found, fallback to demo
            Accounts.get_or_create_demo_user()
          user ->
            Logger.info("Loaded authenticated user: #{user.email}")
            # User found, use it
            user
        end
    end

    Logger.info("Using user: #{user.email} (Google connected: #{!is_nil(user.google_access_token)})")

    # Get conversation ID from params or use first conversation
    conversation_id = params["id"] || get_first_conversation_id(user.id)

    # Load conversation data
    socket = assign_conversation_data(socket, user, conversation_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    conversation_id = socket.assigns.current_conversation.id
    user = socket.assigns.current_user

    # Use real AI agent to process the message
    case Agent.process_and_save_message(user, content, conversation_id) do
      {:ok, _response} ->
        # Reload messages to show the conversation
        messages = Chat.list_messages(conversation_id)
        {:noreply, assign(socket, :messages, messages)}

      {:error, reason} ->
        # Show error message
        error_msg = "Error: #{inspect(reason)}"
        {:ok, _} = Chat.create_message(conversation_id, "assistant", error_msg)

        messages = Chat.list_messages(conversation_id)
        {:noreply, assign(socket, :messages, messages)}
    end
  end

  def handle_event("send_message", _, socket) do
    # Empty message, do nothing
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_thread", _params, socket) do
    user_id = socket.assigns.current_user.id

    # Create new conversation
    {:ok, conversation} = Chat.create_conversation(user_id, %{
      title: "New Chat"
    })

    # Redirect to new conversation
    {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation.id}")}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/chat/#{id}")}
  end

  @impl true
  def handle_event("sync_data", _params, socket) do
    user = socket.assigns.current_user

    # Start sync in background
    Task.start(fn ->
      DataSync.sync_all_data(user)
    end)

    # Update socket with sync status
    socket = put_flash(socket, :info, "Syncing Gmail and HubSpot data in background...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("sync_emails", _params, socket) do
    user = socket.assigns.current_user

    case DataSync.sync_emails(user, async: true) do
      {:ok, _} ->
        socket = put_flash(socket, :info, "Email sync started. This may take a minute...")
        {:noreply, socket}
      {:error, :no_google_token} ->
        socket = put_flash(socket, :error, "Please connect Google account first at /auth/google")
        {:noreply, socket}
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to sync emails: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sync_contacts", _params, socket) do
    user = socket.assigns.current_user

    case DataSync.sync_contacts(user, async: true) do
      {:ok, _} ->
        socket = put_flash(socket, :info, "Contact sync started. This may take a minute...")
        {:noreply, socket}
      {:error, :no_hubspot_token} ->
        socket = put_flash(socket, :error, "Please connect HubSpot account first at /auth/hubspot/authorize")
        {:noreply, socket}
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to sync contacts: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("disconnect_google", _params, socket) do
    require Logger
    user = socket.assigns.current_user

    # Clear Google OAuth tokens
    case Accounts.update_user(user, %{
      google_access_token: nil,
      google_refresh_token: nil,
      google_token_expires_at: nil
    }) do
      {:ok, updated_user} ->
        Logger.info("Disconnected Google for user #{user.email}")

        # Reload with updated user
        socket = assign_conversation_data(socket, updated_user, socket.assigns.current_conversation.id)
        socket = put_flash(socket, :info, "Gmail disconnected. Your synced emails are still available for RAG search.")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to disconnect Google: #{inspect(reason)}")
        socket = put_flash(socket, :error, "Failed to disconnect Gmail")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("disconnect_hubspot", _params, socket) do
    require Logger
    user = socket.assigns.current_user

    # Clear HubSpot OAuth tokens
    case Accounts.update_user(user, %{
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_token_expires_at: nil
    }) do
      {:ok, updated_user} ->
        Logger.info("Disconnected HubSpot for user #{user.email}")

        # Reload with updated user
        socket = assign_conversation_data(socket, updated_user, socket.assigns.current_conversation.id)
        socket = put_flash(socket, :info, "HubSpot disconnected. Your synced contacts are still available for RAG search.")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to disconnect HubSpot: #{inspect(reason)}")
        socket = put_flash(socket, :error, "Failed to disconnect HubSpot")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    conversation_id = params["id"] || get_first_conversation_id(socket.assigns.current_user.id)
    socket = assign_conversation_data(socket, socket.assigns.current_user, conversation_id)

    {:noreply, socket}
  end

  # Private functions

  defp get_first_conversation_id(user_id) do
    case Chat.list_conversations(user_id) do
      [first | _] -> first.id
      [] ->
        # Create default conversation if none exist
        {:ok, conv} = Chat.create_conversation(user_id, %{title: "General Assistance"})
        conv.id
    end
  end

  defp assign_conversation_data(socket, user, conversation_id) do
    conversations = Chat.list_conversations(user.id)
    current_conversation = Chat.get_conversation!(conversation_id)
    messages = Chat.list_messages(conversation_id)
    sync_status = DataSync.get_sync_status(user)

    socket
    |> assign(:current_user, user)
    |> assign(:conversations, conversations)
    |> assign(:current_conversation, current_conversation)
    |> assign(:messages, messages)
    |> assign(:active_tab, "chat")
    |> assign(:context_filter, "all_meetings")
    |> assign(:sync_status, sync_status)
  end
end
