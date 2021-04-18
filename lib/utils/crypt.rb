require 'openssl'

module Crypt
  def self.en(value)
    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.encrypt
    cipher.iv = ENV.fetch('JUBIVOTE_CIPHER_IV')
    cipher.key = ENV.fetch('JUBIVOTE_CIPHER_KEY')
    return cipher.update(value) + cipher.final
  end

  def self.de(value)
    decipher = OpenSSL::Cipher.new('aes-256-cbc')
    decipher.decrypt
    decipher.iv = ENV.fetch('JUBIVOTE_CIPHER_IV')
    decipher.key = ENV.fetch('JUBIVOTE_CIPHER_KEY')
    return decipher.update(value) + decipher.final
  rescue OpenSSL::Cipher::CipherError
    return
  end
end
