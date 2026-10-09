#!/usr/bin/env bash
git config core.hooksPath .githooks && chmod +x .githooks/* scripts/*.sh && echo "hooks installed"
