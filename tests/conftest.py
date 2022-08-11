import pytest


@pytest.fixture
def sudo(accounts):
    return accounts[-1]


@pytest.fixture
def token(sudo, project):
    return sudo.deploy(project.Token)
