SHELL := /bin/bash

.PHONY: help config install start stop restart status doctor logs once uninstall check

CTL := ./bin/tmate-corpoctl

export USER_MAC
export USER_COMMAND_PATH
export REMOTE_INSTALL_WITH_SUDO
export SKIP_SSH_COPY_ID
export TMATE_BIN
export TMATE_SESSION
export TMATE_SOCKET
export TMATE_REFRESH_SECONDS
export TMATE_EMPTY_GRACE_SECONDS
export TMATE_RESTART_ON_DISCONNECT

help:
	@$(CTL) help

config:
	@$(CTL) config

install:
	@$(CTL) install

start:
	@$(CTL) start

stop:
	@$(CTL) stop

restart:
	@$(CTL) restart

status:
	@$(CTL) status

doctor:
	@$(CTL) doctor

logs:
	@$(CTL) logs

once:
	@$(CTL) once

uninstall:
	@$(CTL) uninstall

check:
	@bash -n bin/tmate-corpoctl
	@bash -n bin/tmate-corpo-service
	@bash -n lib/common.sh
