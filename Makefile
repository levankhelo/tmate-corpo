SHELL := /bin/bash

.PHONY: help config install start stop restart status logs once uninstall check

CTL := ./bin/tmate-corpoctl

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
