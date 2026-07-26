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

    # The payment provider's checkout-session id on a Pack purchase; nil on
    # other kinds. Unique, so a replayed webhook can never grant twice.
    field :provider_ref, :string

    belongs_to :user, ActionPoints.Accounts.User
    # Which Extraction a consumption paid for; nil on grants. Unique per
    # Extraction, so one success can never be charged twice.
    belongs_to :extraction, ActionPoints.Meetings.Extraction

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
