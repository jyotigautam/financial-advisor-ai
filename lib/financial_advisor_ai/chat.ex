defmodule FinancialAdvisorAi.Chat do
  @moduledoc """
  The Chat context - manages conversations and messages
  """

  import Ecto.Query, warn: false
  alias FinancialAdvisorAi.Repo
  alias FinancialAdvisorAi.Chat.{Conversation, Message}

  @doc """
  Returns the list of conversations for a user.
  """
  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id and c.archived == false)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation.
  """
  def get_conversation!(id), do: Repo.get!(Conversation, id)

  @doc """
  Gets a conversation with its messages.
  """
  def get_conversation_with_messages(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  @doc """
  Creates a conversation.
  """
  def create_conversation(user_id, attrs \\ %{}) do
    attrs = Map.merge(attrs, %{user_id: user_id})

    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a message in a conversation.
  """
  def create_message(conversation_id, role, content, opts \\ []) do
    attrs = %{
      conversation_id: conversation_id,
      role: role,
      content: content,
      tool_calls: Keyword.get(opts, :tool_calls),
      metadata: Keyword.get(opts, :metadata)
    }

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        # Update conversation timestamp
        conversation = get_conversation!(conversation_id)
        Conversation.changeset(conversation, %{})
        |> Repo.update()

        {:ok, message}
      error -> error
    end
  end

  @doc """
  Lists messages for a conversation.
  """
  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end
end
