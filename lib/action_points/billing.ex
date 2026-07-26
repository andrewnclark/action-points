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
  The Pack on sale: `%{credits: ..., price_pence: ..., currency: ...}`.
  Pricing is config, not code (ADR-0003) — change it freely.
  """
  def pack, do: Map.new(Application.fetch_env!(:action_points, :pack))

  @doc """
  The configured payment-port adapter (`ActionPoints.Billing.PaymentProvider`).
  """
  def payment_provider, do: Application.fetch_env!(:action_points, :payment_provider)

  @doc """
  Grants the Pack's Credits for a completed checkout session — the webhook is
  the only caller (the redirect back from Checkout is untrusted). Exactly once
  per session: `provider_ref` is unique in the ledger, so a replayed webhook
  comes back `:already_granted` and writes nothing.

  Takes a bare `user_id`, not a `Scope`: the caller is Stripe's webhook, where
  no user session exists — the id was carried through Checkout as the session's
  `client_reference_id`.
  """
  def grant_pack_credits(user_id, provider_ref)
      when is_integer(user_id) and is_binary(provider_ref) do
    %CreditTransaction{
      user_id: user_id,
      amount: pack().credits,
      kind: :pack_purchase,
      provider_ref: provider_ref
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:provider_ref,
      name: :credit_transactions_provider_ref_index
    )
    |> Ecto.Changeset.foreign_key_constraint(:user_id)
    |> Repo.insert()
    |> case do
      {:ok, _transaction} ->
        :granted

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :provider_ref),
          do: :already_granted,
          else: {:error, :unknown_user}
    end
  end

  @doc """
  Records the consumption of one Credit by a successful Extraction — the one
  negative ledger entry kind. Meant to run inside the same transaction that
  marks the Extraction successful, so a crash can't charge without delivering
  (nor deliver without charging).
  """
  def consume_extraction_credit!(user_id, extraction_id)
      when is_integer(user_id) and is_integer(extraction_id) do
    Repo.insert!(%CreditTransaction{
      user_id: user_id,
      amount: -1,
      kind: :extraction_consumption,
      extraction_id: extraction_id
    })
  end

  @doc """
  Loads the Credit balance onto the scope, for display wherever the scope goes.
  """
  def with_balance(nil), do: nil

  def with_balance(%Scope{user: %User{}} = scope) do
    %{scope | credit_balance: balance(scope)}
  end
end
