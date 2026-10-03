import pytest

from api import _decimal, _entero, _password_valida


def test_password_requisitos():
    assert _password_valida("Flor123!")
    assert not _password_valida("flor123!")
    assert not _password_valida("Flor1234")
    assert not _password_valida("F1!")


def test_entero_rango():
    assert _entero("5", 1) == 5
    assert _entero("0", 1) is None
    assert _entero("101", 1, 100) is None


def test_decimal():
    assert _decimal("12.50") == 12.5
    assert _decimal("-1") is None
