.PHONY: all fmt init validate plan apply destroy

all: fmt init validate

fmt:
	terraform fmt

init:
	terraform init

validate:
	terraform validate