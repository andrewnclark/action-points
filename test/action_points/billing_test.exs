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

  describe "grant_signup_credit/1" do
    test "cannot grant the signup Credit twice for the same user" do
      user = unconfirmed_user_fixture()

      assert {:error, %Ecto.Changeset{}} = Billing.grant_signup_credit(user)
      assert Billing.balance(Scope.for_user(user)) == 1
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
