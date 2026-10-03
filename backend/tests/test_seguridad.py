from seguridad import es_hash, hash_password, verificar_password


def test_hash_no_guarda_password_en_plano():
    password = "Flor123!"
    guardado = hash_password(password)
    assert guardado != password
    assert es_hash(guardado)


def test_password_hasheada_se_verifica():
    guardado = hash_password("Flor123!")
    assert verificar_password(guardado, "Flor123!") == (True, False)
    assert verificar_password(guardado, "Incorrecta1!") == (False, False)


def test_password_legacy_se_migra():
    assert verificar_password("Flor123!", "Flor123!") == (True, True)
    assert verificar_password("Flor123!", "Otra123!") == (False, False)
