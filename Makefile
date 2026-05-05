SHELL := /bin/bash

.PHONY: help config install start stop restart status doctor logs once publish uninstall check

CTL := ./bin/tmate-corpoctl

export USER_MAC
export USER_COMMAND_PATH
export SKIP_SSH_COPY_ID
export CORPO_SSH_PORT
export USER_REVERSE_PORT
export SSHD_BIN

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

publish: once

uninstall:
	@$(CTL) uninstall

check:
	@bash -n bin/tmate-corpoctl
	@bash -n bin/tmate-corpo-service
	@bash -n lib/common.sh
