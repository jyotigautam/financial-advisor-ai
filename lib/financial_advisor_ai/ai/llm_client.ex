defmodule FinancialAdvisorAi.AI.LLMClient do
  @moduledoc """
  Universal LLM client supporting multiple providers:
  - Google Gemini (FREE!)
  - Anthropic Claude
  """

  require Logger

  @doc """
  Send a chat completion request with optional tool calling support.

  ## Examples

      iex> LLMClient.chat([%{role: "user", content: "Hello!"}])
      {:ok, %{content: "Hi! How can I help you?", tool_calls: nil}}

      iex> LLMClient.chat(messages, tools)
      {:ok, %{content: "...", tool_calls: [%{name: "search_emails", arguments: %{...}}]}}
  """
  def chat(messages, tools \\ [], opts \\ []) do
    provider = Application.get_env(:financial_advisor_ai, :llm_provider, "gemini")

    case provider do
      "gemini" -> chat_gemini(messages, tools, opts)
      "anthropic" -> chat_anthropic(messages, tools, opts)
      _ -> {:error, "Unknown LLM provider: #{provider}"}
    end
  end

  # ============================================================================
  # GEMINI IMPLEMENTATION (FREE!)
  # ============================================================================

  defp chat_gemini(messages, tools, opts) do
    api_key = Application.get_env(:financial_advisor_ai, :gemini_api_key)
    model = Application.get_env(:financial_advisor_ai, :gemini_model, "gemini-2.5-flash")

    if !api_key do
      {:error, "GEMINI_API_KEY not set. Get one free at https://makersuite.google.com/app/apikey"}
    else
      # Use v1 API for gemini-2.5-flash, v1beta for others
      api_version = if String.contains?(model, "1.5"), do: "v1", else: "v1beta"
      url = "https://generativelanguage.googleapis.com/#{api_version}/models/#{model}:generateContent"

      headers = [
        {"x-goog-api-key", api_key},
        {"Content-Type", "application/json"}
      ]

      body = %{
        contents: format_messages_for_gemini(messages),
        generationConfig: %{
          temperature: Keyword.get(opts, :temperature, 0.7),
          maxOutputTokens: Keyword.get(opts, :max_tokens, 2048)
        }
      }

      # Add tool declarations if provided
      # TODO: Properly implement Gemini function calling format
      # body = if tools != [] do
      #   Map.put(body, :tools, [%{functionDeclarations: format_tools_for_gemini(tools)}])
      # else
      #   body
      # end

      case Req.post(url, headers: headers, json: body) do
        {:ok, %{status: 200, body: response}} ->
          parse_gemini_response(response)

        {:ok, %{status: status, body: body}} ->
          Logger.error("Gemini API error: #{status} - #{inspect(body)}")
          {:error, "Gemini API returned status #{status}"}

        {:error, reason} ->
          Logger.error("Gemini request failed: #{inspect(reason)}")
          {:error, "Failed to connect to Gemini: #{inspect(reason)}"}
      end
    end
  end

  defp format_messages_for_gemini(messages) do
    messages
    |> Enum.map(fn msg ->
      role = case msg.role do
        "assistant" -> "model"
        "system" -> "user"  # Gemini doesn't have system role, treat as user
        _ -> msg.role
      end

      %{
        role: role,
        parts: [%{text: msg.content || msg[:text] || ""}]
      }
    end)
  end

  defp format_tools_for_gemini(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters
      }
    end)
  end

  defp parse_gemini_response(%{"candidates" => [candidate | _]}) do
    content = candidate["content"]
    parts = content["parts"] || []

    # Check for function calls
    function_calls = parts
    |> Enum.filter(&Map.has_key?(&1, "functionCall"))
    |> Enum.map(fn part ->
      fc = part["functionCall"]
      %{
        name: fc["name"],
        arguments: fc["args"] || %{}
      }
    end)

    # Get text response
    text = parts
    |> Enum.filter(&Map.has_key?(&1, "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("")

    tool_calls = if function_calls == [], do: nil, else: function_calls

    {:ok, %{
      content: text,
      tool_calls: tool_calls,
      finish_reason: candidate["finishReason"]
    }}
  end

  defp parse_gemini_response(response) do
    Logger.error("Unexpected Gemini response: #{inspect(response)}")
    {:error, "Unexpected response format from Gemini"}
  end

  # ============================================================================
  # ANTHROPIC CLAUDE IMPLEMENTATION
  # ============================================================================

  defp chat_anthropic(messages, tools, opts) do
    api_key = Application.get_env(:financial_advisor_ai, :anthropic_api_key)
    model = Application.get_env(:financial_advisor_ai, :anthropic_model, "claude-3-5-sonnet-20241022")

    if !api_key do
      {:error, "ANTHROPIC_API_KEY not set"}
    else
      # Separate system message from other messages
      {system_message, user_messages} = extract_system_message(messages)

      request_body = %{
        model: model,
        messages: user_messages,
        max_tokens: Keyword.get(opts, :max_tokens, 2048),
        temperature: Keyword.get(opts, :temperature, 0.7)
      }

      request_body = if system_message do
        Map.put(request_body, :system, system_message)
      else
        request_body
      end

      request_body = if tools != [] do
        Map.put(request_body, :tools, Enum.map(tools, &format_tool_for_anthropic/1))
      else
        request_body
      end

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"Content-Type", "application/json"}
      ]

      case Req.post("https://api.anthropic.com/v1/messages", json: request_body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          parse_anthropic_response(response)

        {:ok, %{status: status, body: body}} ->
          {:error, "Anthropic API returned status #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Failed to connect to Anthropic: #{inspect(reason)}"}
      end
    end
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, &(&1.role == "system")) do
      nil -> {nil, messages}
      sys_msg -> {sys_msg.content, Enum.reject(messages, &(&1.role == "system"))}
    end
  end

  defp format_tool_for_anthropic(tool) do
    %{
      name: tool.name,
      description: tool.description,
      input_schema: tool.parameters
    }
  end

  defp parse_anthropic_response(%{"content" => content} = response) do
    text = content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("")

    tool_uses = content
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn use ->
      %{
        name: use["name"],
        arguments: use["input"]
      }
    end)

    tool_calls = if tool_uses == [], do: nil, else: tool_uses

    {:ok, %{
      content: text,
      tool_calls: tool_calls,
      finish_reason: response["stop_reason"]
    }}
  end

  @doc """
  Stream chat responses (for real-time UI updates).
  Returns a stream of response chunks.
  """
  def chat_stream(messages, tools \\ [], opts \\ []) do
    provider = Application.get_env(:financial_advisor_ai, :llm_provider, "gemini")

    case provider do
      "gemini" -> {:error, "Streaming not yet implemented for Gemini"}
      "openai" -> {:error, "Streaming not yet implemented for OpenAI"}
      _ -> {:error, "Streaming not supported for #{provider}"}
    end
  end
end
