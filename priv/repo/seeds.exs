# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias FinancialAdvisorAi.Repo
alias FinancialAdvisorAi.Accounts.User
alias FinancialAdvisorAi.Chat.{Conversation, Message}

# Clear existing data (only in dev)
if Mix.env() == :dev do
  Repo.delete_all(Message)
  Repo.delete_all(Conversation)
  Repo.delete_all(User)
end

# Create demo user
{:ok, user} = %User{}
|> User.changeset(%{
  email: "demo@example.com",
  name: "Demo User",
  google_id: "demo_google_id_123"
})
|> Repo.insert()

IO.puts("✅ Created demo user: #{user.email}")

# Create a conversation
{:ok, conversation} = %Conversation{}
|> Conversation.changeset(%{
  user_id: user.id,
  title: "General Assistance"
})
|> Repo.insert()

IO.puts("✅ Created conversation: #{conversation.title}")

# Add sample messages simulating a real conversation about meetings
messages = [
  %{
    role: "assistant",
    content: "I can answer questions about any Jump meeting. What do you want to know?",
    metadata: %{type: "greeting"}
  },
  %{
    role: "user",
    content: "Find meetings I've had with Bill and Tim this month",
    metadata: %{type: "query"}
  },
  %{
    role: "assistant",
    content: "Sure, here are some recent meetings that you, Bill, and Tim all attended. I found 2 in May.",
    metadata: %{
      type: "response",
      meetings: [
        %{
          date: "8 Thursday",
          time: "12 - 1:30pm",
          title: "Quarterly All Team Meeting",
          attendees: ["Bill", "Tim", "Sarah", "John"]
        },
        %{
          date: "16 Friday",
          time: "1 - 2pm",
          title: "Strategy review",
          attendees: ["Bill", "Tim"]
        }
      ]
    }
  },
  %{
    role: "assistant",
    content: "I can summarize these meetings, schedule a follow up, and more!",
    metadata: %{type: "suggestion"}
  }
]

for msg <- messages do
  {:ok, _message} = %Message{}
  |> Message.changeset(Map.merge(msg, %{conversation_id: conversation.id}))
  |> Repo.insert()
end

IO.puts("✅ Created #{length(messages)} sample messages")

# Create another conversation for history
{:ok, conversation2} = %Conversation{}
|> Conversation.changeset(%{
  user_id: user.id,
  title: "Email Questions"
})
|> Repo.insert()

messages2 = [
  %{
    role: "user",
    content: "Who mentioned baseball in their emails?",
    metadata: %{}
  },
  %{
    role: "assistant",
    content: "John Smith mentioned his son plays baseball in an email on May 5th. He was asking about scheduling a practice session.",
    metadata: %{type: "rag_response"}
  }
]

for msg <- messages2 do
  {:ok, _message} = %Message{}
  |> Message.changeset(Map.merge(msg, %{conversation_id: conversation2.id}))
  |> Repo.insert()
end

IO.puts("✅ Created second conversation with #{length(messages2)} messages")
IO.puts("\n🎉 Demo data created successfully!")
IO.puts("You can now run: iex -S mix phx.server")
IO.puts("Then visit: http://localhost:4000")
