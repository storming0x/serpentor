import pytest

from eth_utils import to_checksum_address

DAY = 86400
WEEK = 7 * DAY


@pytest.fixture(scope="session")
def gov(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def whale_amount():
    yield 10**22


@pytest.fixture(scope="session")
def whale(accounts, yfi, whale_amount):
    a = accounts[1]
    yfi.mint(a, whale_amount, sender=a)
    yield a


@pytest.fixture(scope="session")
def shark_amount():
    yield 10**20


@pytest.fixture(scope="session")
def shark(accounts, yfi, shark_amount):
    a = accounts[2]
    yfi.mint(a, shark_amount, sender=a)
    yield a


@pytest.fixture(scope="session")
def fish_amount():
    yield 10**18


@pytest.fixture(scope="session")
def fish(accounts, yfi, fish_amount):
    a = accounts[3]
    yfi.mint(a, fish_amount, sender=a)
    yield a


@pytest.fixture(scope="session")
def panda(accounts):
    yield accounts[4]


@pytest.fixture(scope="session")
def doggie(accounts):
    yield accounts[5]


@pytest.fixture(scope="session")
def bunny(accounts):
    yield accounts[6]


@pytest.fixture(scope="session")
def yfi(project, gov):
    yield gov.deploy(project.Token, "YFI")

