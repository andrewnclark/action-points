defmodule ActionPoints.Billing.CreditTransaction do
  @moduledoc """
  One append-only entry in the Credit ledger.

  Grants are positive, consumptions negative; a user's balance is the sum of
  their entries. The application never updates or deletes entries — corrections
  are new entries (ADR-0003). Deleting a user cascades away their ledger.
  """
  use Ecto.Schema

  schema "credit_transactions" do
    field :amount, :integer
    field :kind, Ecto.Enum, values: [:signup_grant, :pack_purchase, :extraction_consumption]

    belongs_to :user, ActionPoints.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
