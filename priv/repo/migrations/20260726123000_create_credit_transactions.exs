defmodule ActionPoints.Repo.Migrations.CreateCreditTransactions do
  use Ecto.Migration

  def change do
    create table(:credit_transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :amount, :integer, null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:credit_transactions, [:user_id])
    create constraint(:credit_transactions, :amount_must_be_nonzero, check: "amount <> 0")

    create unique_index(:credit_transactions, [:user_id],
             where: "kind = 'signup_grant'",
             name: :credit_transactions_one_signup_grant_per_user
           )
  end
end
