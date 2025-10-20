defmodule FinancialAdvisorAi.AI.Agent do
  @moduledoc """
  Main AI Agent orchestrator.

  Handles:
  - RAG (Retrieval Augmented Generation) for context
  - Tool calling to interact with Gmail, Calendar, HubSpot
  - Multi-turn conversations with memory
  - Task persistence for long-running operations
  """

  require Logger

  alias FinancialAdvisorAi.AI.{LLMClient, ToolRegistry, IntentParser}
  alias FinancialAdvisorAi.Memory.Search
  alias FinancialAdvisorAi.{Chat, Accounts}
  alias FinancialAdvisorAi.Accounts.User

  @system_prompt """
  You are a helpful AI assistant for financial advisors.

  When the user asks questions, I will automatically provide you with relevant context from their emails and contacts.
  This context will appear in the user's message under "CONTEXT (from user's emails and contacts)".

  Use this context to answer questions accurately. If the context contains relevant information, use it directly in your response.

  If the context doesn't contain enough information to answer the question, say so clearly.

  Be concise, professional, and helpful. Focus on providing accurate information based on the context provided.
  """

  @doc """
  Process a user message and generate a response.

  This is the main entry point for the AI agent.

  ## Options
    * `:conversation_id` - Conversation ID for context (required)
    * `:use_rag` - Whether to use RAG for context (default: true)
    * `:max_iterations` - Max tool calling iterations (default: 5)

  ## Examples

      iex> Agent.process_message(user, "Find emails from Bill about baseball",
        conversation_id: conv_id)
      {:ok, %{response: "I found 3 emails...", tool_calls_made: [...]}}
  """
  def process_message(%User{} = user, message_content, opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    use_rag = Keyword.get(opts, :use_rag, true)

    # First, check if this is a direct tool call using intent parser
    case IntentParser.parse_intent(message_content) do
      {:tool, tool_name, args} ->
        Logger.info("Intent detected: calling tool #{tool_name} with args: #{inspect(args)}")

        # Execute the tool directly
        result = ToolRegistry.execute_tool(tool_name, args, user)

        # Format response based on result
        response = format_tool_response(tool_name, result)

        {:ok, %{
          response: response,
          tool_calls_made: [%{tool_name: tool_name, arguments: args, result: result}]
        }}

      {:clarify, message} ->
        # Need more information from user
        {:ok, %{response: message, tool_calls_made: []}}

      {:chat, _} ->
        # Regular chat message - use RAG and LLM
        max_iterations = Keyword.get(opts, :max_iterations, 5)
        history = Chat.list_messages(conversation_id)
        messages = build_messages(history, message_content, user, use_rag)
        tools = ToolRegistry.get_all_tools()
        run_agent_loop(user, messages, tools, max_iterations, [])
    end
  end

  @doc """
  Run agent loop with tool calling support.

  This handles the iterative process of:
  1. Send messages to LLM
  2. Check if LLM wants to call tools
  3. Execute tools
  4. Add tool results to conversation
  5. Continue until LLM returns final answer
  """
  defp run_agent_loop(user, messages, tools, iterations_left, tool_calls_made) do
    if iterations_left <= 0 do
      {:error, "Max iterations reached"}
    else
      case LLMClient.chat(messages, tools) do
        {:ok, %{content: content, tool_calls: nil}} ->
          # No tool calls - final answer
          {:ok, %{
            response: content,
            tool_calls_made: Enum.reverse(tool_calls_made)
          }}

        {:ok, %{content: _content, tool_calls: tool_calls}} when is_list(tool_calls) ->
          # LLM wants to call tools
          Logger.info("Agent calling #{length(tool_calls)} tools")

          # Execute all tool calls
          tool_results = Enum.map(tool_calls, fn %{name: name, arguments: args} ->
            Logger.info("Executing tool: #{name} with args: #{inspect(args)}")

            result = ToolRegistry.execute_tool(name, args, user)

            %{
              tool_name: name,
              arguments: args,
              result: result
            }
          end)

          # Add tool results to messages
          assistant_message = %{
            role: "assistant",
            content: "Calling tools...",
            tool_calls: tool_calls
          }

          tool_messages = Enum.map(tool_results, fn %{tool_name: name, result: result} ->
            %{
              role: "function",
              name: name,
              content: format_tool_result(result)
            }
          end)

          new_messages = messages ++ [assistant_message] ++ tool_messages
          new_tool_calls_made = tool_calls_made ++ tool_results

          # Continue loop
          run_agent_loop(user, new_messages, tools, iterations_left - 1, new_tool_calls_made)

        {:error, reason} ->
          Logger.error("LLM call failed: #{inspect(reason)}")
          {:error, "Failed to generate response: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Build messages array for LLM including system prompt, history, and RAG context.
  """
  defp build_messages(history, new_message, user, use_rag) do
    # System message
    system_msg = %{role: "system", content: @system_prompt}

    # Conversation history (excluding system messages)
    history_msgs = history
    |> Enum.filter(fn msg -> msg.role != "system" end)
    |> Enum.map(fn msg ->
      %{role: msg.role, content: msg.content || ""}
    end)

    # Get RAG context if enabled
    rag_context = if use_rag do
      case should_use_rag?(new_message) do
        true ->
          Logger.info("RAG triggered for query: #{new_message}")
          case Search.get_rag_context(user.id, new_message) do
            {:ok, context} ->
              Logger.info("RAG context retrieved (#{String.length(context)} chars)")
              Logger.debug("RAG context: #{String.slice(context, 0..500)}...")
              context
            {:error, reason} ->
              Logger.warning("RAG context retrieval failed: #{inspect(reason)}")
              nil
          end
        false ->
          Logger.info("RAG not triggered for query: #{new_message}")
          nil
      end
    else
      nil
    end

    # User message with optional RAG context
    user_msg_content = if rag_context do
      """
      CONTEXT (from user's emails and contacts):
      #{rag_context}

      USER QUESTION:
      #{new_message}
      """
    else
      new_message
    end

    user_msg = %{role: "user", content: user_msg_content}

    # Combine all messages
    [system_msg] ++ history_msgs ++ [user_msg]
  end

  @doc """
  Determine if RAG should be used for this query.

  RAG is helpful for questions about past emails, meetings, or contacts.
  """
  defp should_use_rag?(message) do
    message_lower = String.downcase(message)

    # Keywords that suggest RAG would be helpful
    rag_keywords = [
      "email", "emails", "sent", "received", "wrote",
      "meeting", "meetings", "calendar", "event",
      "contact", "client", "customer",
      "said", "told", "mentioned", "discussed",
      "last time", "previously", "before",
      "find", "search", "look up", "show me",
      "what is", "what are", "tell me about", "info",
      "update", "application", "project", "task"
    ]

    # If message is a question or contains keywords, use RAG
    is_question = String.contains?(message_lower, ["?", "what", "who", "when", "where", "why", "how"])
    has_keyword = Enum.any?(rag_keywords, fn keyword ->
      String.contains?(message_lower, keyword)
    end)

    is_question or has_keyword
  end

  @doc """
  Format tool execution result for LLM.
  """
  defp format_tool_result({:ok, result}) do
    Jason.encode!(result)
  end

  defp format_tool_result({:error, reason}) do
    Jason.encode!(%{error: reason})
  end

  @doc """
  Format tool response for user display.
  """
  defp format_tool_response("list_calendar_events", {:ok, %{events: events}}) when is_list(events) do
    if events == [] do
      "You have no upcoming events in your calendar."
    else
      event_list = events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, idx} ->
        "#{idx}. #{event["summary"]} - #{event["start"]}"
      end)
      |> Enum.join("\n")

      "Here are your upcoming calendar events:\n\n#{event_list}"
    end
  end

  defp format_tool_response("create_calendar_event", {:ok, %{id: id, htmlLink: link}}) do
    "✓ Event created successfully! You can view it here: #{link}"
  end

  defp format_tool_response("send_email", {:ok, %{id: _id}}) do
    "✓ Email sent successfully!"
  end

  defp format_tool_response("get_hubspot_contact", {:ok, contact}) when is_map(contact) do
    "Found contact: #{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]} (#{contact["properties"]["email"]})"
  end

  defp format_tool_response(_tool_name, {:ok, result}) do
    "✓ Action completed successfully.\n\n#{inspect(result, pretty: true)}"
  end

  defp format_tool_response(_tool_name, {:error, reason}) do
    "I encountered an error: #{inspect(reason)}"
  end

  @doc """
  Simplified version for quick responses without full agent loop.
  Useful for simple questions that don't need tools.
  """
  def quick_response(%User{} = user, message, opts \\ []) do
    conversation_id = opts[:conversation_id]

    messages = if conversation_id do
      history = Chat.list_messages(conversation_id)
      build_messages(history, message, user, false)
    else
      [
        %{role: "system", content: @system_prompt},
        %{role: "user", content: message}
      ]
    end

    case LLMClient.chat(messages, []) do
      {:ok, %{content: content}} ->
        {:ok, content}

      error ->
        error
    end
  end

  @doc """
  Process a message and save the interaction to the database.

  This is a higher-level function that:
  1. Saves the user message
  2. Runs the agent
  3. Saves the assistant response
  4. Returns the response
  """
  def process_and_save_message(%User{} = user, message_content, conversation_id) do
    # Save user message
    {:ok, _user_msg} = Chat.create_message(conversation_id, "user", message_content)

    # Process with agent
    case process_message(user, message_content, conversation_id: conversation_id) do
      {:ok, %{response: response, tool_calls_made: tool_calls}} when is_binary(response) and response != "" ->
        # Save assistant response with metadata
        metadata = %{
          tool_calls: Enum.map(tool_calls, fn tc ->
            %{
              tool: tc.tool_name,
              success: match?({:ok, _}, tc.result)
            }
          end)
        }

        case Chat.create_message(conversation_id, "assistant", response, metadata: metadata) do
          {:ok, _assistant_msg} ->
            {:ok, response}

          {:error, changeset} ->
            Logger.error("Failed to save assistant message: #{inspect(changeset)}")
            error_msg = "I encountered an error saving my response."
            {:ok, _} = Chat.create_message(conversation_id, "assistant", error_msg)
            {:error, "Failed to save response"}
        end

      {:ok, %{response: response}} ->
        # Empty or nil response
        Logger.warning("Agent returned empty response: #{inspect(response)}")
        error_msg = "I'm sorry, I couldn't generate a proper response. Please try rephrasing your question."
        {:ok, _} = Chat.create_message(conversation_id, "assistant", error_msg)
        {:error, "Empty response from agent"}

      {:error, reason} ->
        # Save error response
        error_msg = "I encountered an error: #{inspect(reason)}"
        {:ok, _} = Chat.create_message(conversation_id, "assistant", error_msg)

        {:error, reason}
    end
  end

  @doc """
  Generate a title for a conversation based on the first message.
  """
  def generate_conversation_title(first_message) do
    # Simple heuristic - use first few words
    first_message
    |> String.split()
    |> Enum.take(6)
    |> Enum.join(" ")
    |> String.slice(0..50)
  end

  @doc """
  Check if user has necessary OAuth tokens for agent features.
  Returns list of missing integrations.
  """
  def check_user_integrations(%User{} = user) do
    missing = []

    missing = if !user.google_access_token, do: ["Google" | missing], else: missing
    missing = if !user.hubspot_access_token, do: ["HubSpot" | missing], else: missing

    if missing == [] do
      {:ok, :all_connected}
    else
      {:missing, missing}
    end
  end
end
