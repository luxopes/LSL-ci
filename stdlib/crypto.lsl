# lsl: internal-abi
# lsl: link libcrypto.so.3
# Kryptografie nad systémovým OpenSSL (libcrypto, cíl linux-x86_64-gnu):
# náhodné bajty, haše SHA-2 (najednou i po částech, soubory po blocích),
# HMAC, klíče EC P-256 (vytvoření, PEM a DER, SubjectPublicKeyInfo),
# podpis ECDSA se SHA-256 (podpis DER jako SHA256withECDSA v Javě),
# certifikáty X.509 podepsané sebou samým a porovnání v konstantním čase.
# Modul nemá vlastní kryptografii, jen volá OpenSSL.
#
# Klíč (EVP_PKEY) a certifikát (X509) jsou surové ukazatele (Int); paměť
# uvolní key_free a certificate_free (GC je nevidí). Data jsou String nebo
# ByteArray, haše a podpisy ByteArray. Chyby OpenSSL jsou CryptoError
# s textem z fronty chyb.

EVP_PKEY_EC = 408
NID_COMMON_NAME = 13
NID_BASIC_CONSTRAINTS = 87
MBSTRING_UTF8 = 4097
BIO_CTRL_INFO = 3
O_RDONLY = 0
O_CLOEXEC = 524288

function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

function bytes_data(bytes):
    return __lsl_qbe_load64(__lsl_address(bytes) + 24)
end

function from_c(address):
    raw = ptr(address)
    if raw == 0:
        return ""
    end
    length = __lsl_qbe_call1(__lsl_symbol("strlen"), raw)
    bytes = __lsl_byte_zeros(length)
    call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(bytes), raw, length)
    return __lsl_text_from_bytes(bytes, 0, length)
end

function bytes_from_c(address, length):
    bytes = __lsl_byte_zeros(ptr(length))
    if ptr(length) > 0:
        call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(bytes), ptr(address), ptr(length))
    end
    return bytes
end

function data_pointer(data):
    if type(data) == "String":
        return cstr(data)
    end
    return bytes_data(data)
end

function data_length(data):
    if type(data) == "String":
        return __lsl_text_byte_length(data)
    end
    return len(data)
end

# Poslední chyba OpenSSL jako text (fronta se vyprázdní).
function openssl_error():
    code = __lsl_qbe_call0(__lsl_symbol("ERR_get_error"))
    call __lsl_qbe_call0(__lsl_symbol("ERR_clear_error"))
    if code == 0:
        return "unknown OpenSSL error"
    end
    buffer = __lsl_byte_zeros(256)
    call __lsl_qbe_call3(__lsl_symbol("ERR_error_string_n"), code, bytes_data(buffer), 256)
    return from_c(bytes_data(buffer))
end

function fail(action):
    Error(CryptoError: action + ": " + openssl_error())
end

# --- bajty a text ---

# Malá písmena hex (sha256 → 64 znaků).
function hex(data):
    digits = "0123456789abcdef"
    pointer = data_pointer(data)
    count = data_length(data)
    parts = []
    index = 0
    while index < count:
        byte = __lsl_qbe_load8(pointer + index)
        parts.append(digits[byte >> 4] + digits[byte & 15])
        index += 1
    end
    return "".join(parts)
end

function hex_value(character):
    code = ord(character)
    if code >= 48 and code <= 57:
        return code - 48
    elif code >= 97 and code <= 102:
        return code - 87
    elif code >= 65 and code <= 70:
        return code - 55
    end
    Error(ValueError: "invalid hex digit: " + character)
end

# ByteArray z textu hex (malá i velká písmena, sudý počet znaků).
function from_hex(text):
    if len(text) % 2 != 0:
        Error(ValueError: "hex text must have an even length")
    end
    result = ByteArray()
    index = 0
    while index < len(text):
        result.append(hex_value(text[index]) * 16 + hex_value(text[index + 1]))
        index += 2
    end
    return result
end

# Porovnání v konstantním čase (CRYPTO_memcmp): délka se neskrývá, obsah ano.
function constant_time_equal(a, b):
    length = data_length(a)
    if length != data_length(b):
        return False
    end
    if length == 0:
        return True
    end
    return __lsl_qbe_icall3(__lsl_symbol("CRYPTO_memcmp"), data_pointer(a), data_pointer(b), length) == 0
end

# Kryptograficky bezpečné náhodné bajty (RAND_bytes).
function random_bytes(count):
    result = __lsl_byte_zeros(ptr(count))
    if ptr(count) > 0:
        if __lsl_qbe_icall2(__lsl_symbol("RAND_bytes"), bytes_data(result), ptr(count)) != 1:
            call fail("RAND_bytes")
        end
    end
    return result
end

# --- haše ---

# Algoritmus podle jména: "sha256", "sha384", "sha512", "sha1".
function digest_algorithm(name):
    if name == "sha256":
        return __lsl_qbe_call0(__lsl_symbol("EVP_sha256"))
    elif name == "sha384":
        return __lsl_qbe_call0(__lsl_symbol("EVP_sha384"))
    elif name == "sha512":
        return __lsl_qbe_call0(__lsl_symbol("EVP_sha512"))
    elif name == "sha1":
        return __lsl_qbe_call0(__lsl_symbol("EVP_sha1"))
    end
    Error(ValueError: "unknown hash algorithm: " + String(name))
end

# Haš dat najednou: ByteArray (sha256 32 bajtů).
function hash(name, data):
    algorithm = digest_algorithm(name)
    output = __lsl_byte_zeros(64)
    size = __lsl_byte_zeros(4)
    if __lsl_qbe_icall6(__lsl_symbol("EVP_Digest"), data_pointer(data), data_length(data), bytes_data(output), bytes_data(size), algorithm, 0) != 1:
        call fail("EVP_Digest")
    end
    return bytes_from_c(bytes_data(output), __lsl_qbe_load32(bytes_data(size)))
end

function sha256(data):
    return hash("sha256", data)
end

# Haš po částech pro velká data: hash_new → hash_update … → hash_final
# (uvolní kontext). Vrací ukazatel kontextu.
function hash_new(name):
    algorithm = digest_algorithm(name)
    context = __lsl_qbe_call0(__lsl_symbol("EVP_MD_CTX_new"))
    if context == 0:
        call fail("EVP_MD_CTX_new")
    end
    if __lsl_qbe_icall3(__lsl_symbol("EVP_DigestInit_ex"), context, algorithm, 0) != 1:
        call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
        call fail("EVP_DigestInit_ex")
    end
    return context
end

function hash_update(context, data):
    if __lsl_qbe_icall3(__lsl_symbol("EVP_DigestUpdate"), ptr(context), data_pointer(data), data_length(data)) != 1:
        call fail("EVP_DigestUpdate")
    end
    return 0
end

function hash_final(context):
    output = __lsl_byte_zeros(64)
    size = __lsl_byte_zeros(4)
    status = __lsl_qbe_icall3(__lsl_symbol("EVP_DigestFinal_ex"), ptr(context), bytes_data(output), bytes_data(size))
    call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), ptr(context))
    if status != 1:
        call fail("EVP_DigestFinal_ex")
    end
    return bytes_from_c(bytes_data(output), __lsl_qbe_load32(bytes_data(size)))
end

# Haš souboru po blocích 1 MiB (soubor se nenačítá celý do paměti).
function hash_file(name, path):
    fd = __lsl_qbe_icall2(__lsl_symbol("open"), cstr(path), O_RDONLY | O_CLOEXEC)
    if fd < 0:
        Error(FileError: "cannot open " + String(path))
    end
    context = hash_new(name)
    buffer = __lsl_byte_zeros(1048576)
    loop:
        count = __lsl_qbe_call3(__lsl_symbol("read"), fd, bytes_data(buffer), 1048576)
        if count <= 0:
            break
        end
        if __lsl_qbe_icall3(__lsl_symbol("EVP_DigestUpdate"), context, bytes_data(buffer), count) != 1:
            call __lsl_qbe_call1(__lsl_symbol("close"), fd)
            call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
            call fail("EVP_DigestUpdate")
        end
    end
    call __lsl_qbe_call1(__lsl_symbol("close"), fd)
    if count < 0:
        call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
        Error(FileError: "cannot read " + String(path))
    end
    return hash_final(context)
end

# HMAC (RFC 2104) s algoritmem name.
function hmac(name, key, data):
    algorithm = digest_algorithm(name)
    output = __lsl_byte_zeros(64)
    size = __lsl_byte_zeros(4)
    result = __lsl_qbe_call7(__lsl_symbol("HMAC"), algorithm, data_pointer(key), data_length(key), data_pointer(data), data_length(data), bytes_data(output), bytes_data(size))
    if result == 0:
        call fail("HMAC")
    end
    return bytes_from_c(bytes_data(output), __lsl_qbe_load32(bytes_data(size)))
end

# --- paměťový BIO pro PEM ---

function bio_from(data):
    bio = __lsl_qbe_call2(__lsl_symbol("BIO_new_mem_buf"), data_pointer(data), data_length(data))
    if bio == 0:
        call fail("BIO_new_mem_buf")
    end
    return bio
end

function bio_new():
    bio = __lsl_qbe_call1(__lsl_symbol("BIO_new"), __lsl_qbe_call0(__lsl_symbol("BIO_s_mem")))
    if bio == 0:
        call fail("BIO_new")
    end
    return bio
end

# Obsah BIO jako String a uvolnění BIO.
function bio_text(bio):
    cell = __lsl_byte_zeros(8)
    length = __lsl_qbe_call4(__lsl_symbol("BIO_ctrl"), ptr(bio), BIO_CTRL_INFO, 0, bytes_data(cell))
    bytes = bytes_from_c(__lsl_qbe_load64(bytes_data(cell)), length)
    call __lsl_qbe_call1(__lsl_symbol("BIO_free"), ptr(bio))
    return __lsl_text_from_bytes(bytes, 0, len(bytes))
end

# DER přes funkci i2d_*: nejdřív délka, pak zápis do bufferu.
# (__lsl_symbol bere jen literál, proto adresa funkce a jméno pro chybu.)
function der_of(code, function_name, object):
    length = __lsl_qbe_icall2(ptr(code), ptr(object), 0)
    if length <= 0:
        call fail(function_name)
    end
    output = __lsl_byte_zeros(length)
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), bytes_data(output))
    if __lsl_qbe_icall2(ptr(code), ptr(object), bytes_data(cell)) != length:
        call fail(function_name)
    end
    return output
end

# --- klíče ---

# Nový klíč EC P-256 (secp256r1, prime256v1).
function ec_generate():
    context = __lsl_qbe_call3(__lsl_symbol("EVP_PKEY_CTX_new_from_name"), 0, cstr("EC"), 0)
    if context == 0:
        call fail("EVP_PKEY_CTX_new_from_name")
    end
    key_cell = __lsl_byte_zeros(8)
    ok = __lsl_qbe_icall1(__lsl_symbol("EVP_PKEY_keygen_init"), context) == 1
    if ok:
        ok = __lsl_qbe_icall2(__lsl_symbol("EVP_PKEY_CTX_set_group_name"), context, cstr("P-256")) == 1
    end
    if ok:
        ok = __lsl_qbe_icall2(__lsl_symbol("EVP_PKEY_generate"), context, bytes_data(key_cell)) == 1
    end
    call __lsl_qbe_call1(__lsl_symbol("EVP_PKEY_CTX_free"), context)
    if not ok:
        call fail("EC key generation")
    end
    return __lsl_qbe_load64(bytes_data(key_cell))
end

function key_free(key):
    call __lsl_qbe_call1(__lsl_symbol("EVP_PKEY_free"), ptr(key))
    return 0
end

# Soukromý klíč jako PEM PKCS#8 bez šifrování ("BEGIN PRIVATE KEY").
function key_to_pem(key):
    bio = bio_new()
    if __lsl_qbe_icall7(__lsl_symbol("PEM_write_bio_PrivateKey"), bio, ptr(key), 0, 0, 0, 0, 0) != 1:
        call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
        call fail("PEM_write_bio_PrivateKey")
    end
    return bio_text(bio)
end

# Soukromý klíč z PEM (PKCS#8 i tradiční "BEGIN EC PRIVATE KEY").
function key_from_pem(text):
    bio = bio_from(text)
    key = __lsl_qbe_call4(__lsl_symbol("PEM_read_bio_PrivateKey"), bio, 0, 0, 0)
    call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
    if key == 0:
        call fail("PEM_read_bio_PrivateKey")
    end
    return key
end

# Soukromý klíč jako DER PKCS#8.
function key_to_der(key):
    info = __lsl_qbe_call1(__lsl_symbol("EVP_PKEY2PKCS8"), ptr(key))
    if info == 0:
        call fail("EVP_PKEY2PKCS8")
    end
    der = der_of(__lsl_symbol("i2d_PKCS8_PRIV_KEY_INFO"), "i2d_PKCS8_PRIV_KEY_INFO", info)
    call __lsl_qbe_call1(__lsl_symbol("PKCS8_PRIV_KEY_INFO_free"), info)
    return der
end

# Soukromý klíč z DER (PKCS#8 nebo tradiční).
function key_from_der(data):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), data_pointer(data))
    key = __lsl_qbe_call3(__lsl_symbol("d2i_AutoPrivateKey"), 0, bytes_data(cell), data_length(data))
    if key == 0:
        call fail("d2i_AutoPrivateKey")
    end
    return key
end

# Veřejný klíč jako DER SubjectPublicKeyInfo (otisk = sha256 z něj).
function public_key_der(key):
    return der_of(__lsl_symbol("i2d_PUBKEY"), "i2d_PUBKEY", key)
end

function public_key_pem(key):
    bio = bio_new()
    if __lsl_qbe_icall2(__lsl_symbol("PEM_write_bio_PUBKEY"), bio, ptr(key)) != 1:
        call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
        call fail("PEM_write_bio_PUBKEY")
    end
    return bio_text(bio)
end

# Veřejný klíč (EVP_PKEY jen s veřejnou částí) z DER SubjectPublicKeyInfo.
function public_key_from_der(data):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), data_pointer(data))
    key = __lsl_qbe_call3(__lsl_symbol("d2i_PUBKEY"), 0, bytes_data(cell), data_length(data))
    if key == 0:
        call fail("d2i_PUBKEY")
    end
    return key
end

function public_key_from_pem(text):
    bio = bio_from(text)
    key = __lsl_qbe_call4(__lsl_symbol("PEM_read_bio_PUBKEY"), bio, 0, 0, 0)
    call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
    if key == 0:
        call fail("PEM_read_bio_PUBKEY")
    end
    return key
end

# Druh klíče: "EC", "RSA", "ED25519" … (EVP_PKEY_get0_type_name).
function key_type(key):
    return from_c(__lsl_qbe_call1(__lsl_symbol("EVP_PKEY_get0_type_name"), ptr(key)))
end

# Křivka klíče EC ("prime256v1" pro P-256), jinak "".
function key_curve(key):
    if __lsl_qbe_icall1(__lsl_symbol("EVP_PKEY_get_base_id"), ptr(key)) != EVP_PKEY_EC:
        return ""
    end
    buffer = __lsl_byte_zeros(80)
    size = __lsl_byte_zeros(8)
    if __lsl_qbe_icall4(__lsl_symbol("EVP_PKEY_get_group_name"), ptr(key), bytes_data(buffer), 80, bytes_data(size)) != 1:
        return ""
    end
    return from_c(bytes_data(buffer))
end

# --- podpisy ---

# Podpis dat: ECDSA se SHA-256, podpis DER (SHA256withECDSA).
function sign(key, data):
    context = __lsl_qbe_call0(__lsl_symbol("EVP_MD_CTX_new"))
    if __lsl_qbe_icall5(__lsl_symbol("EVP_DigestSignInit"), context, 0, __lsl_qbe_call0(__lsl_symbol("EVP_sha256")), 0, ptr(key)) != 1:
        call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
        call fail("EVP_DigestSignInit")
    end
    size = __lsl_byte_zeros(8)
    status = __lsl_qbe_icall5(__lsl_symbol("EVP_DigestSign"), context, 0, bytes_data(size), data_pointer(data), data_length(data))
    signature = __lsl_byte_zeros(__lsl_qbe_load64(bytes_data(size)))
    if status == 1:
        status = __lsl_qbe_icall5(__lsl_symbol("EVP_DigestSign"), context, bytes_data(signature), bytes_data(size), data_pointer(data), data_length(data))
    end
    call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
    if status != 1:
        call fail("EVP_DigestSign")
    end
    return bytes_from_c(bytes_data(signature), __lsl_qbe_load64(bytes_data(size)))
end

# Ověření podpisu DER veřejným klíčem: True/False (chybný podpis není chyba).
function verify(key, data, signature):
    context = __lsl_qbe_call0(__lsl_symbol("EVP_MD_CTX_new"))
    if __lsl_qbe_icall5(__lsl_symbol("EVP_DigestVerifyInit"), context, 0, __lsl_qbe_call0(__lsl_symbol("EVP_sha256")), 0, ptr(key)) != 1:
        call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
        call fail("EVP_DigestVerifyInit")
    end
    status = __lsl_qbe_icall5(__lsl_symbol("EVP_DigestVerify"), context, data_pointer(signature), data_length(signature), data_pointer(data), data_length(data))
    call __lsl_qbe_call1(__lsl_symbol("EVP_MD_CTX_free"), context)
    call __lsl_qbe_call0(__lsl_symbol("ERR_clear_error"))
    return status == 1
end

# --- certifikáty X.509 ---

# Certifikát podepsaný sebou samým: subjekt i vydavatel CN = common_name,
# platnost days dní od teď, SHA-256, BasicConstraints CA:FALSE (kritické),
# náhodné kladné sériové číslo. Vrací ukazatel X509.
function self_signed_certificate(key, common_name, days=36500):
    certificate = __lsl_qbe_call0(__lsl_symbol("X509_new"))
    if certificate == 0:
        call fail("X509_new")
    end
    serial = random_bytes(8)
    number = __lsl_qbe_load64(bytes_data(serial)) & 9223372036854775807
    if number == 0:
        number = 1
    end
    ok = __lsl_qbe_icall2(__lsl_symbol("X509_set_version"), certificate, 2) == 1
    ok = ok and __lsl_qbe_icall2(__lsl_symbol("ASN1_INTEGER_set_int64"), __lsl_qbe_call1(__lsl_symbol("X509_get_serialNumber"), certificate), number) == 1
    ok = ok and __lsl_qbe_call2(__lsl_symbol("X509_gmtime_adj"), __lsl_qbe_call1(__lsl_symbol("X509_getm_notBefore"), certificate), 0) != 0
    ok = ok and __lsl_qbe_call2(__lsl_symbol("X509_gmtime_adj"), __lsl_qbe_call1(__lsl_symbol("X509_getm_notAfter"), certificate), ptr(days) * 86400) != 0
    ok = ok and __lsl_qbe_icall2(__lsl_symbol("X509_set_pubkey"), certificate, ptr(key)) == 1
    name = __lsl_qbe_call1(__lsl_symbol("X509_get_subject_name"), certificate)
    ok = ok and __lsl_qbe_icall7(__lsl_symbol("X509_NAME_add_entry_by_txt"), name, cstr("CN"), MBSTRING_UTF8, cstr(common_name), -1, -1, 0) == 1
    ok = ok and __lsl_qbe_icall2(__lsl_symbol("X509_set_issuer_name"), certificate, name) == 1
    if ok:
        extension = __lsl_qbe_call4(__lsl_symbol("X509V3_EXT_conf_nid"), 0, 0, NID_BASIC_CONSTRAINTS, cstr("critical,CA:FALSE"))
        ok = extension != 0
        if ok:
            ok = __lsl_qbe_icall3(__lsl_symbol("X509_add_ext"), certificate, extension, -1) == 1
            call __lsl_qbe_call1(__lsl_symbol("X509_EXTENSION_free"), extension)
        end
    end
    ok = ok and __lsl_qbe_icall3(__lsl_symbol("X509_sign"), certificate, ptr(key), __lsl_qbe_call0(__lsl_symbol("EVP_sha256"))) > 0
    if not ok:
        call __lsl_qbe_call1(__lsl_symbol("X509_free"), certificate)
        call fail("self-signed certificate")
    end
    return certificate
end

function certificate_free(certificate):
    call __lsl_qbe_call1(__lsl_symbol("X509_free"), ptr(certificate))
    return 0
end

function certificate_to_pem(certificate):
    bio = bio_new()
    if __lsl_qbe_icall2(__lsl_symbol("PEM_write_bio_X509"), bio, ptr(certificate)) != 1:
        call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
        call fail("PEM_write_bio_X509")
    end
    return bio_text(bio)
end

function certificate_from_pem(text):
    bio = bio_from(text)
    certificate = __lsl_qbe_call4(__lsl_symbol("PEM_read_bio_X509"), bio, 0, 0, 0)
    call __lsl_qbe_call1(__lsl_symbol("BIO_free"), bio)
    if certificate == 0:
        call fail("PEM_read_bio_X509")
    end
    return certificate
end

# Celý certifikát v DER (otisk LocalSend = sha256 z něj).
function certificate_der(certificate):
    return der_of(__lsl_symbol("i2d_X509"), "i2d_X509", certificate)
end

function certificate_from_der(data):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), data_pointer(data))
    certificate = __lsl_qbe_call3(__lsl_symbol("d2i_X509"), 0, bytes_data(cell), data_length(data))
    if certificate == 0:
        call fail("d2i_X509")
    end
    return certificate
end

# Veřejný klíč certifikátu (nový EVP_PKEY, uvolní key_free).
function certificate_public_key(certificate):
    key = __lsl_qbe_call1(__lsl_symbol("X509_get_pubkey"), ptr(certificate))
    if key == 0:
        call fail("X509_get_pubkey")
    end
    return key
end

# DER SubjectPublicKeyInfo z certifikátu (otisk LuxDrop = sha256 z něj).
function certificate_spki(certificate):
    key = certificate_public_key(certificate)
    der = public_key_der(key)
    call key_free(key)
    return der
end

# CN subjektu certifikátu ("" když chybí).
function certificate_common_name(certificate):
    buffer = __lsl_byte_zeros(256)
    length = __lsl_qbe_icall4(__lsl_symbol("X509_NAME_get_text_by_NID"), __lsl_qbe_call1(__lsl_symbol("X509_get_subject_name"), ptr(certificate)), NID_COMMON_NAME, bytes_data(buffer), 256)
    if length < 0:
        return ""
    end
    return from_c(bytes_data(buffer))
end

# Sedí soukromý klíč k certifikátu?
function certificate_matches_key(certificate, key):
    result = __lsl_qbe_icall2(__lsl_symbol("X509_check_private_key"), ptr(certificate), ptr(key)) == 1
    call __lsl_qbe_call0(__lsl_symbol("ERR_clear_error"))
    return result
end
