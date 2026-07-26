defmodule ActionPoints.Repo.Migrations.AddExtractionToCreditTransactions do
  use Ecto.Migration

  def change do
    alter table(:credit_transactions) do
      # Which Extraction a consumption paid for. Nilified (not deleted) if the
      # Extraction goes away — the ledger is append-only and survives its cause.
      add :extraction_id, references(:extractions, on_delete: :nilify_all)
    end

    # One Extraction can never be charged twice.
    create unique_index(:credit_transactions, [:extraction_id],
             where: "extraction_id IS NOT NULL",
             name: :credit_transactions_one_consumption_per_extraction
           )
  end
end
