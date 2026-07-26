defmodule ActionPoints.Vault do
  @moduledoc """
  Application-layer encryption for secrets at rest — currently the Linear API
  key on a sink connection. AES-256-GCM with a key from application config
  (`SINK_ENCRYPTION_KEY` in production).

  Ciphertext layout: a version byte, then the 12-byte IV, the 16-byte tag,
  and the ciphertext.
  """

  @aad "ActionPoints.Vault"

  def encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, @aad, true)

    <<1, iv::binary, tag::binary, ciphertext::binary>>
  end

  def decrypt(<<1, iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  def decrypt(_ciphertext), do: :error

  defp key do
    :action_points
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:key)
    |> decode_key()
  end

  defp decode_key(key) when byte_size(key) == 32, do: key
  defp decode_key(base64), do: Base.decode64!(base64)
end
