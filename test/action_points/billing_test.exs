defmodule ActionPoints.BillingTest do
  use ActionPoints.DataCase, async: true

  import ActionPoints.AccountsFixtures

  alias ActionPoints.Accounts
  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Billing
  alias ActionPoints.Billing.CreditTransaction

  describe "registration seeds the Free Meeting" do
    test "registering a user records exactly one ledger grant of one Credit" do
      {:ok, user} = Accounts.register_user(valid_user_attributes())

      assert [%CreditTransaction{amount: 1, kind: :signup_grant}] =
               Repo.all(from t in CreditTransaction, where: t.user_id == ^user.id)
    end

    test "a failed registration grants nothing" do
      {:ok, _user} = Accounts.register_user(valid_user_attributes(email: "taken@example.com"))
      assert {:error, %Ecto.Changeset{}} = Accounts.register_user(%{email: "taken@example.com"})

      assert Repo.aggregate(CreditTransaction, :count) == 1
    end
  end

  describe "format_price/1" do
    test "a round price loses the pennies" do
      assert Billing.format_price(%{currency: "gbp", price_pence: 500}) == "£5"
    end

    test "a non-round price keeps both decimal places" do
      assert Billing.format_price(%{currency: "gbp", price_pence: 750}) == "£7.50"
      assert Billing.format_price(%{currency: "gbp", price_pence: 1234}) == "£12.34"
    end

    test "a currency with no symbol falls back to its code" do
      assert Billing.format_price(%{currency: "usd", price_pence: 500}) == "USD 5"
    end

    # Not the figure — that is config's to change freely (ADR-0003) — but that
    # what `pack/0` returns is something this function can format at all.
    test "the configured Pack is formattable as it stands" do
      assert is_binary(Billing.format_price(Billing.pack()))
    end
  end

  describe "grant_signup_credit/1" do
    test "cannot grant the signup Credit twice for the same user" do
      user = unconfirmed_user_fixture()

      assert {:error, %Ecto.Changeset{}} = Billing.grant_signup_credit(user)
      assert Billing.balance(Scope.for_user(user)) == 1
    end
  end

  describe "grant_pack_credits/2" do
    test "grants the Pack's 15 Credits keyed to the checkout session" do
      user = unconfirmed_user_fixture()

      assert Billing.grant_pack_credits(user.id, "cs_1") == :granted
      assert Billing.balance(Scope.for_user(user)) == 16

      assert [%CreditTransaction{amount: 15, kind: :pack_purchase, provider_ref: "cs_1"}] =
               Repo.all(
                 from t in CreditTransaction,
                   where: t.user_id == ^user.id and t.kind == :pack_purchase
               )
    end

    test "a repeated grant for the same checkout session is a no-op" do
      user = unconfirmed_user_fixture()

      assert Billing.grant_pack_credits(user.id, "cs_1") == :granted
      assert Billing.grant_pack_credits(user.id, "cs_1") == :already_granted
      assert Billing.balance(Scope.for_user(user)) == 16
    end

    test "a second checkout session grants again" do
      user = unconfirmed_user_fixture()

      assert Billing.grant_pack_credits(user.id, "cs_1") == :granted
      assert Billing.grant_pack_credits(user.id, "cs_2") == :granted
      assert Billing.balance(Scope.for_user(user)) == 31
    end

    test "a grant for an unknown user is refused" do
      assert Billing.grant_pack_credits(-1, "cs_1") == {:error, :unknown_user}
      assert Repo.aggregate(CreditTransaction, :count) == 0
    end
  end

  describe "balance/1" do
    test "is the sum of the user's ledger transactions" do
      user = unconfirmed_user_fixture()

      Repo.insert!(%CreditTransaction{user_id: user.id, amount: 15, kind: :pack_purchase})

      Repo.insert!(%CreditTransaction{
        user_id: user.id,
        amount: -1,
        kind: :extraction_consumption
      })

      assert Billing.balance(Scope.for_user(user)) == 15
    end

    test "only counts the scoped user's transactions" do
      user = unconfirmed_user_fixture()
      other = unconfirmed_user_fixture()
      Repo.insert!(%CreditTransaction{user_id: other.id, amount: 15, kind: :pack_purchase})

      assert Billing.balance(Scope.for_user(user)) == 1
    end
  end
end
