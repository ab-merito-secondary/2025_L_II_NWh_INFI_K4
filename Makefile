deps:
	pip install -r requirements.txt; \
	pip install -r test_requirements.txt
lint:
	flake8 hello_world test
run:
	python main.py
.PHONY: test
test:
	PYTHONPATH=. py.test --verbose -s
docker_build:
	docker build -t hello-world-printer .
docker_run: docker_build
	docker run \
	--name hello-world-printer-app \
	-p 5000:5000 \
	-d hello-world-printer
TAG=$(USERNAME)/hello-world-printer:$(TAGNAME)
docker_push: docker_build
	@set -e; \
	trap 'docker logout' EXIT; \
	echo "$${DOCKER_PASSWORD}" | docker login --username $(USERNAME) --password-stdin; \
	docker tag hello-world-printer $(TAG); \
	docker push $(TAG)
docker_verify:
	docker manifest inspect $(TAG) > /dev/null
	@echo "Obraz $(TAG) jest w rejestrze"
# --- Deploy do Azure Container Apps ---------------------------------------
RESOURCE_GROUP ?= hello-rg
APP_NAME ?= hello-world-printer
VERSION ?= $(CIRCLE_SHA1)
DEPLOY_IMAGE ?= docker.io/$(USERNAME)/hello-world-printer:$(VERSION)
REVISION_SUFFIX ?= $(shell printf '%.7s' "$(VERSION)")

check_version:
	@test -n "$(VERSION)" || (echo "Brak VERSION/CIRCLE_SHA1 - podaj: make <target> VERSION=<sha>" && exit 1)
oidc_debug:
	@echo "$${CIRCLE_OIDC_TOKEN}" | cut -d. -f2 | base64 -d 2>/dev/null; echo
azure_login:
	@test -n "$${CIRCLE_OIDC_TOKEN}" || (echo "Brak CIRCLE_OIDC_TOKEN - job musi miec context" && exit 1)
	@az login --service-principal \
		-u "$${AZURE_CLIENT_ID}" \
		--tenant "$${AZURE_TENANT_ID}" \
		--federated-token "$${CIRCLE_OIDC_TOKEN}" \
		--output none
	@az config set extension.use_dynamic_install=yes_without_prompt
azure_deploy: check_version
	az containerapp update \
		--name $(APP_NAME) \
		--resource-group $(RESOURCE_GROUP) \
		--image $(DEPLOY_IMAGE) \
		--revision-suffix $(REVISION_SUFFIX) \
		--output none
	@echo "Wdrozono $(DEPLOY_IMAGE) jako rewizje $(APP_NAME)--$(REVISION_SUFFIX)"
smoke_test:
	@FQDN=$$(az containerapp show -n $(APP_NAME) -g $(RESOURCE_GROUP) \
		--query properties.configuration.ingress.fqdn -o tsv | tr -d '\r'); \
	echo "Sprawdzam https://$$FQDN/"; \
	for i in $$(seq 1 10); do \
		curl -fsS "https://$$FQDN/" && exit 0; \
		sleep 5; \
	done; \
	echo "Aplikacja nie odpowiada"; exit 1
deploy: azure_login azure_deploy smoke_test
.PHONY: docker_verify check_version oidc_debug azure_login azure_deploy smoke_test deploy