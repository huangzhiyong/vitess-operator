.PHONY: build release-build unit-test integration-test generate generate-and-diff generate-operator-yaml push-only push

IMAGE_REGISTRY:=docker.io
IMAGE_TAG:=latest

IMAGE:=planetscale/vitess-operator

IMAGE_NAME:=$(IMAGE_REGISTRY)/$(IMAGE)

# Enable Go modules
export GO111MODULE=on

# Regular operator-sdk build is good for development because it does the actual
# build outside Docker, so it uses your cached modules.
build:
	go run github.com/operator-framework/operator-sdk/cmd/operator-sdk build $(IMAGE_NAME):$(IMAGE_TAG) --image-build-args '--no-cache'

# Release build is slow but self-contained (doesn't depend on anything in your
# local machine). We use this for automated builds that we publish.
release-build:
	docker build -f build/Dockerfile.release -t $(IMAGE_NAME):$(IMAGE_TAG) .

unit-test:
	pkgs="$$(go list ./... | grep -v '/test/integration/')" && \
		go test -i $${pkgs} && \
		go test $${pkgs}

integration-test:
	tools/get-kube-binaries.sh
	go test -i ./test/integration/...
	PATH="$(PWD)/tools/_bin:$(PATH)" go test -v -timeout 5m ./test/integration/... -args --logtostderr -v=6

# Hack GOPATH: this works only if $GOPATH/src/planetscale.dev/vitess-operator computes to the current directory.
# operator-sdk needs GOPATH to be set.
export GOPATH=$(shell realpath ../../..)

generate:
	go run github.com/operator-framework/operator-sdk/cmd/operator-sdk generate k8s
	go run sigs.k8s.io/controller-tools/cmd/controller-gen crd:trivialVersions=true,maxDescLen=0 paths="./pkg/apis/planetscale/v2" output:crd:artifacts:config=./deploy/crds
	find deploy/crds -name '*.yaml' | xargs go run ./cmd/trim-crd
	go run github.com/ahmetb/gen-crd-api-reference-docs -api-dir ./pkg/apis -config docs/api/config.json -template-dir docs/api/template -out-file docs/api/index.html

generate-and-diff: generate
	git add --all
	git diff HEAD
	@echo 'If this test fails, it is because the git diff is non-empty after running "make generate".'
	@echo 'To correct this, locally run "make generate", commit the changes, and re-run tests.'
	git diff HEAD --quiet --exit-code

generate-operator-yaml:
	go run github.com/kubernetes-sigs/kustomize build ./deploy > build/_output/operator.yaml

push-only: DATE=$(shell date -I)
push-only: GITHASH=$(shell git rev-parse HEAD)
push-only:
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):$(DATE)-$(GITHASH)
	docker push $(IMAGE_NAME):$(IMAGE_TAG)
	docker push $(IMAGE_NAME):$(DATE)-$(GITHASH)

push: build
push: push-only
