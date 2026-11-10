"""Keep personal Git settings out of temporary repository fixtures."""
import os
from unittest.mock import patch


def isolated_git_environment():
    return patch.dict(os.environ, {
        'GIT_CONFIG_GLOBAL': os.devnull,
        'GIT_CONFIG_SYSTEM': os.devnull,
        'GIT_CONFIG_NOSYSTEM': '1',
    })
