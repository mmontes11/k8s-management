CERT_MANAGER_VERSION ?= v1.18.0
CERT_MANAGER_URL ?= https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.crds.yaml

.PHONY: cert-manager-crds
cert-manager-crds: ### Get cert-manager CRDs to be installed by flux.
	curl -sSLo infrastructure/cert-manager/crds/crds.yaml $(CERT_MANAGER_URL)
