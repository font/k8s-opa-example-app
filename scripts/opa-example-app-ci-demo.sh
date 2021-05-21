#/usr/bin/env bash

# Recorded with the doitlive recorder
#doitlive shell: /bin/bash
#doitlive prompt: damoekri
#doitlive speed: 3
#doitlive commentecho: false

# I have a Kubernetes cluster running here with Tekton and Gatekeeper installed.

kubectl version
tkn version

# I'm currently at the root of our opa-example-app repository that we're using to
# demo and here's the contents of the repo.

ls

# This application is a simple hello world web application containing the Go
# source code and Dockerfile for building its image.

vi main.go
vi Dockerfile

# Let's say you're a developer and the application is already deployed and
# running.

curl opa.ifontlabs.com

# The application is built and deployed via Tekton Pipelines. As a developer, you
# come in on a work day morning and you have a task to do to make some changes to
# the application.

vi main.go

# Now you want to test the application so you build a container image to test it
# before deploying to production.

docker build --no-cache -t gcr.io/ifontlabs/k8s-opa-example-app .

# You then push the container image to a container registry repository that you
# have access to.

docker push gcr.io/ifontlabs/k8s-opa-example-app

# Now in order to deploy your test image and test it, we'll need to make changes
# to the deployment manifest for the application.

sed -i 's|quay.io/ifont|gcr.io/ifontlabs|' ./config/k8s/deployment.yaml

# Then we verify the changes you want to commit.

git diff

# Then commit and push the changes.

git commit -a -m "Update Hello World message"
git push

# Of course the use of a test registry such as this example is exactly the kind
# of thing you want to prevent, so while the commit is flowing through the Tekton
# Pipeline we can look at the Gatekeeper ConstraintTemplate and Constraint
# resources that are configured to prevent unauthorized registries from being
# used to deploy images.
#
# Here we can see the constrainttemplate defines a new CRD K8sTrustedRegistries
# that takes an array of trusted registries. It then defines a rego policy
# template that given the set of trusted registries and container spec as input
# parameters, will make sure that the container image specified in the
# container spec is using a registry that's in the list of trusted registries.

vi config/opa/trustedregistries-template.yaml

# Then we've defined a custom resource instance of the K8sTrustedRegistry CRD
# that lists the Kubernetes API resources e.g. Pods and Deployments that embeds
# the container spec as a template. The Pods and Deployments that exists in the
# opa-example-app namespace will be passed to Gatekeeper along with the trusted
# registry quay.io. Lastly, the enforcement action for this policy is set to
# deny so that we actively enforce this policy.

vi config/opa/trustedregistries.yaml

# Now let's observe how the pipeline run is doing using the Tekton CLI tool
# `tkn`:

tkn pipelinerun logs --follow --last

# We can see we successfully fetched the repository, built and pushed the image,
# but when we go to apply the manifest, it failed.
#
# Why did it fail? Well the error reads:
#
# > Admission webhook 'validation.gatekeeper.sh' denied the request: denied by
# > trusted-registries, which is the name of our custom resource shown previously,
# > container opa-example-app has an invalid image registry, allowed registries are
# > 'quay.io'
#
# So you can see our Gatekeeper policy acted as a last resort safety net that
# has prevented the deployment of an image from an untrusted registry.
#
# OK great, but the developer had to wait for the entire pipeline to nearly
# complete in order to eventually see it fail. That's rather time consuming and
# expensive. Wouldn't it be great if we can "shift left" so that we add these
# safety checks earlier in the pipeline so the developer can receive more
# immediate feedback? That's precisely what we'll do next.

clear

# Here we're deploying a different pipeline that adds a step earlier in the
# pipeline to deploy the application using a server-dry-run. That way we can
# effectively determine if Gatekeeper will succeed or fail this pipeline run as
# soon as possible.

kubectl apply -f config/tekton/pipeline/pipeline-dryrun.yaml

# Now let's re-run the last pipeline run. We'll just alt-tab to switch over to
# our Tekton Dashboard, and we can see the list of pipeline runs. Here we can
# quickly restart the last pipeline run.
#
# Now let's switch back and observe how the pipeline run is doing using the
# Tekton CLI tool again:

tkn pipelinerun logs --follow --last

# We can see that we first fetch the repository successfully, but now we
# attempt to apply the OPA policy immediately after using server-dry-run and
# it's failed for the same exact reason, because the container opa-example-app
# has an invalid image registry, allowed registries are "quay.io".
#
# Ok cool, so we've managed to give the developer feedback earlier.
#
# All this was done using Gatekeeper, but there's another alternative using
# Conftest that we'll try now.

clear

# This particular pipeline introduces a step to evaluate our policy using the
# Conftest task hosted on the Tekton Hub at hub.tekton.dev.

kubectl apply -f config/tekton/pipeline/pipeline-conftest.yaml

# Now let's re-run the last pipeline run. <alt-tab>
#
# Let's observe the pipeline run again:

tkn pipelinerun logs --follow --last

# Keep in mind we can still leave Gatekeeper to be a last-resort safety-net to
# verify policies before the pipeline completes and deploys anything, but
# Conftest can be used earlier in the pipeline as well instead of relying on
# server-dry-run. Conftest is also really valuable in evaluating policies for
# structured data that is not in the form of Kubernetes APIs such as
# Deployments, Services, and CRDs.
#
# Here you can see we have the same failure via conftest.

clear

# Ok, let's circle back to the developer scenario. Let's say the developer gets
# approval to use the registry that previously violated the policy. As a
# cluster admin, we can use gitops to make changes and/or make runtime changes
# to Gatekeeper to modify the policy. For example, here we modify the runtime
# policy being used by Gatekeeper to add the additional trusted registry:

kubectl edit k8strustedregistries.constraints.gatekeeper.sh trusted-registries

# Then using gitops, we'll also have to modify the policy that conftest is
# using. This policy would typically be stored in a separate repo, but we're
# using the same repo as our test application for example purposes.

vi config/opa/trustedregistries.rego

# Commit and push the change

git commit -a -m "Add gcr.io as trusted registry in conftest rego policy"
git push

# Now let's watch the pipeline run one last time.

tkn pipelinerun logs --follow --last

# We then check that we successfully deployed the application:

curl opa.ifontlabs.com
