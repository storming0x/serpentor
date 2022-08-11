import ape
from ape import project, chain
import pytest

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


def test_token_setup(token):
    assert token.name() == "Test Token"
    assert token.symbol() == "TEST"