defmodule ActionPoints.Repo.Migrations.AddProviderRefToCreditTransactions do
  use Ecto.Migration

  def change do
    alter table(:credit_transactions) do
      add :provider_ref, :string
    end

    # One grant per checkout session: the webhook's idempotency lives here.
    create unique_index(:credit_transactions, [:provider_ref],
             where: "provider_ref IS NOT NULL",
             name: :credit_transactions_provider_ref_index
           )
  end
end
