defmodule ActionPoints.Billing do
  @moduledoc """
  The Credit ledger.

  Credits are the unit of entitlement: one Credit is consumed by one successful
  Extraction. Every grant and consumption is an append-only
  `ActionPoints.Billing.CreditTransaction` row; a user's balance is derived by
  summing their entries (ADR-0003).
  """

  import Ecto.Query

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Accounts.User
  alias ActionPoints.Billing.CreditTransaction
  alias ActionPoints.Repo

  @signup_grant_amount 1

  @doc """
  Returns the Credit balance for the scoped user.
  """
  def balance(%Scope{user: %User{id: user_id}}) do
    Repo.one(
      from t in CreditTransaction,
        where: t.user_id == ^user_id,
        select: coalesce(sum(t.amount), 0)
    )
  end

  @doc """
  Grants the Free Meeting: the single signup Credit every new account receives.

  Enforced to at most one per user by a partial unique index, so a repeat call
  returns `{:error, changeset}` rather than double-granting.
  """
  def grant_signup_credit(%User{id: user_id}) do
    %CreditTransaction{user_id: user_id, amount: @signup_grant_amount, kind: :signup_grant}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:user_id,
      name: :credit_transactions_one_signup_grant_per_user
    )
    |> Repo.insert()
  end

  @doc """
  Loads the Credit balance onto the scope, for display wherever the scope goes.
  """
  def with_balance(nil), do: nil

  def with_balance(%Scope{user: %User{}} = scope) do
    %{scope | credit_balance: balance(scope)}
  end
end
