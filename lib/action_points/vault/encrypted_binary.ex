defmodule ActionPoints.Vault.EncryptedBinary do
  @moduledoc """
  Ecto type for a string encrypted at rest via `ActionPoints.Vault`: plaintext
  in the struct, ciphertext in the database column.
  """

  use Ecto.Type

  alias ActionPoints.Vault

  @impl true
  def type, do: :binary

  @impl true
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl true
  def dump(plaintext) when is_binary(plaintext), do: {:ok, Vault.encrypt(plaintext)}
  def dump(_value), do: :error

  @impl true
  def load(ciphertext) when is_binary(ciphertext) do
    case Vault.decrypt(ciphertext) do
      {:ok, plaintext} -> {:ok, plaintext}
      :error -> :error
    end
  end

  def load(_value), do: :error
end
