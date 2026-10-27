# Modul crypto nad OpenSSL: testovací vektory SHA-256 (FIPS 180-2), HMAC
# (RFC 4231), ECDSA P-256 (RFC 6979 A.2.5) a kruhové převody klíčů,
# podpisů a certifikátů.
load crypto

print crypto.hex(crypto.sha256(""))
print crypto.hex(crypto.sha256("abc"))
print crypto.hex(crypto.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
context = crypto.hash_new("sha256")
chunk = "a" * 1000
for index in rang(1000):
    call crypto.hash_update(context, chunk)
end
print crypto.hex(crypto.hash_final(context))
print crypto.hex(crypto.hash("sha384", "abc"))[0:32]
print crypto.hex(crypto.hmac("sha256", "Jefe", "what do ya want for nothing?"))

path = "/tmp/lsl-crypto-hash-file"
call writefile(path, "abc")
print "file:", crypto.hex(crypto.hash_file("sha256", path)) == crypto.hex(crypto.sha256("abc"))
call remove_path(path)

# RFC 6979 A.2.5: P-256, SHA-256, zpráva "sample".
spki = crypto.from_hex("3059301306072a8648ce3d020106082a8648ce3d03010703420004" + "60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6" + "7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299")
signature = crypto.from_hex("3046022100" + "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716" + "022100" + "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")
public = crypto.public_key_from_der(spki)
print "rfc6979 type:", crypto.key_type(public), crypto.key_curve(public)
print "rfc6979 valid:", crypto.verify(public, "sample", signature)
print "rfc6979 other message:", crypto.verify(public, "sample!", signature)
print "spki round trip:", crypto.constant_time_equal(crypto.public_key_der(public), spki)
call crypto.key_free(public)

key = crypto.ec_generate()
print "generated:", crypto.key_type(key), crypto.key_curve(key)
pem = crypto.key_to_pem(key)
print "pkcs8 pem:", pem.startswith("-----BEGIN PRIVATE KEY-----")
again = crypto.key_from_pem(pem)
print "pem round trip:", crypto.constant_time_equal(crypto.public_key_der(again), crypto.public_key_der(key))
der_again = crypto.key_from_der(crypto.key_to_der(key))
print "der round trip:", crypto.constant_time_equal(crypto.public_key_der(der_again), crypto.public_key_der(key))
message = "LuxDrop hello"
signed = crypto.sign(key, message)
print "signature der:", signed[0] == 48
print "verify:", crypto.verify(again, message, signed), crypto.verify(again, message + ".", signed)
public_pem = crypto.public_key_pem(key)
public_again = crypto.public_key_from_pem(public_pem)
print "public pem verify:", crypto.verify(public_again, message, signed)

certificate = crypto.self_signed_certificate(key, "LuxDrop 0123456789abcdef", 36500)
print "cn:", crypto.certificate_common_name(certificate)
print "matches key:", crypto.certificate_matches_key(certificate, key), crypto.certificate_matches_key(certificate, crypto.ec_generate())
print "spki:", crypto.constant_time_equal(crypto.certificate_spki(certificate), crypto.public_key_der(key))
cert_pem = crypto.certificate_to_pem(certificate)
print "cert pem:", cert_pem.startswith("-----BEGIN CERTIFICATE-----")
from_pem = crypto.certificate_from_pem(cert_pem)
der = crypto.certificate_der(certificate)
print "cert der:", der[0] == 48, crypto.constant_time_equal(crypto.certificate_der(from_pem), der)
from_der = crypto.certificate_from_der(der)
print "fingerprint length:", len(crypto.hex(crypto.sha256(crypto.certificate_der(from_der))))
call crypto.certificate_free(from_der)
call crypto.certificate_free(from_pem)
call crypto.certificate_free(certificate)

print "random:", len(crypto.random_bytes(32)), crypto.constant_time_equal(crypto.random_bytes(16), crypto.random_bytes(16))
print "compare:", crypto.constant_time_equal("abc", "abc"), crypto.constant_time_equal("abc", "abd"), crypto.constant_time_equal("abc", "ab")
print "hex:", crypto.hex(crypto.from_hex("00FFa5")), len(crypto.from_hex(""))
try:
    call crypto.key_from_pem("not a key")
else:
    print "bad pem:", String(last_error()).startswith("CryptoError: PEM_read_bio_PrivateKey")
end
