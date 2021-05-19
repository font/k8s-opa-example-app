# opa-example-app

OPA Example App

## Install Dependencies

Before proceeding with this tutorial, you'll need to install the following:
1. Install the tekton [piplines and
   triggers](https://github.com/tektoncd/triggers/blob/master/docs/getting-started/README.md#install-dependencies).
   This tutorial was constructed using pipelines `v0.24.1` and triggers
   `v0.13.0`.
1. Install the TektonCD Dashboard by following these
   [instructions](https://github.com/tektoncd/dashboard#install-dashboard).
   This tutorial was constructed using dashboard `v0.16.1`.
   Once installed, you can install the following Ingress resources to expose it
   via the same load balancer IP address being used by the other Ingress
   resources. Be sure to modify the host field to provide your own fully
   qualified domain name.
   ```bash
   kubectl apply -f ./config/tekton/dashboard/ingress.yaml
   ```
1. If using GCP, follow the [instructions for using the Nginx Ingress
   Controller](https://github.com/tektoncd/triggers/blob/main/docs/eventlisteners.md#exposing-an-eventlistener-outside-of-the-cluster)
   pasted here for convenience:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.46.0/deploy/static/provider/cloud/deploy.yaml
   ```
1. Install OPA Gatekeeper by following these
   [instructions](https://github.com/open-policy-agent/gatekeeper#installation).
   This tutorial was constructed using OPA Gatekeeper `v3.1.0-beta.7`.
1. Install [docker](https://docs.docker.com/install/).

## Fork This Repository

You'll want to fork this repository in order run through the tutorial so that
you can commit and push changes to trigger builds.

## Configure the cluster

- Create the Namespace where the resoures will live:

```bash
kubectl create namespace opa-example-app
kubectl create namespace opa-example-app-trigger
```

- Set the namespace for the `current-context`:

```bash
kubectl config set-context $(kubectl config current-context) --namespace opa-example-app-trigger
```

- Create the secret to access your container registry. If using Quay, you can
  create a robot account and provide it the necessary permissions to push to
  your container registry repo.

```bash
kubectl create secret docker-registry regcred \
                    --docker-server=<your-registry-server> \
                    --docker-username=<your-name> \
                    --docker-password=<your-pword> \
                    --docker-email=<your-email>
```

- Create the trigger admin service account, role and rolebinding

```bash
kubectl apply -f ./config/tekton/rbac/admin-role.yaml
```

- Create the webhook user, role and rolebinding

```bash
kubectl apply -f ./config/tekton/rbac/webhook-role.yaml
```

- Create the app deploy role and rolebinding in the namespace that will host
  the opa-example-app:

```bash
kubectl -n opa-example-app apply -f ./config/tekton/rbac/app-role.yaml
```

## Install the Tasks, Pipeline and Trigger

## Install the Tasks

To install the tasks run:

```bash
kubectl apply -f ./config/tekton/task/git-clone.yaml
kubectl apply -f ./config/tekton/task/kaniko.yaml
kubectl apply -f ./config/tekton/task/kubernetes-actions.yaml
```

### Install the Pipeline

To install the pipeline run:

```bash
kubectl apply -f ./config/tekton/pipeline/pipeline.yaml
```

### Install the TriggerTemplate, TriggerBinding and EventListener

Be sure to replace the `IMAGE` param field with the respective container
registry and repository to use for pushing the built
image. Then run:

```bash
kubectl apply -f ./config/tekton/trigger/
```

## Add Webhook

From here you can either do this manually using the
`./config/tekton/webhook/ingress.yaml` ingress manifest to set up with http
only, or automate it using the following steps which sets up https using a
self-signed CA.

### Add Ingress

#### Add Ingress Task

```bash
kubectl apply -f ./config/tekton/webhook/create-ingress.yaml
```

#### Run Ingress Task

Be sure to replace the `ExternalDomain` parameter value with your FQDN. This
will be used by the GitHub webhook to reach the ingress in your cluster in
order to pass the relevent GitHub commit details to the `EventListener` service
running in your cluster. Then run:

```bash
kubectl apply -f ./config/tekton/webhook/ingress-run.yaml
```
### Add GitHub Webhook

From here you can either do this manually via the GitHub web console by adding
a new webhook using similar instructions from
[here](https://github.com/openshift/pipelines-tutorial/#configure-webhook-manually),
or automate it using the following steps.

#### Add GitHub Webhook Task

Create the GitHub webhook task by running:

```bash
kubectl apply -f ./config/tekton/webhook/create-webhook.yaml
```

#### Run GitHub Webhook Task

You will need to create a [GitHub Personal Access
Token](https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line#creating-a-token)
with the following access:

- public_repo
- admin:repo_hook

Next, create a secret like so with your access token.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: webhook-secret
    namespace: opa-example-app
    stringData:
      token: YOUR-GITHUB-ACCESS-TOKEN
        secret: random-string-data
```

Next you'll want to edit the `webhook-run.yaml` file:
- Modify the `GitHubOrg` and `GitHubUser` fields to match your setup.
- Modify the `ExternalDomain` field to match the FQDN used in
  `ingress-run.yaml` for configuring the GitHub webhook to use this FQDN to
  talk to the `EventListener`.

Then Create the webhook task:

```bash
kubectl apply -f ./config/tekton/webhook/webhook-run.yaml
```

## Watch the Trigger and Pipeline Work!

Commit and push an empty commit to your development repo.

```bash
git commit -a -m "build commit" --allow-empty && git push origin mybranch
```

## Install OPA Gatekeeper ConstraintTemplate and Constraint

First we'll install the `ConstraintTemplate` and `K8sTrustedRegistries`
constraint to prevent untrusted registries from being used.

```bash
kubectl apply -f ./config/opa/trustedregistries-template.yaml
kubectl apply -f ./config/opa/trustedregistries.yaml
```

## Update Deployment Image Registry

In order to exercise the OPA policy, we'll need to attempt to use an untrusted
registry:

```bash
sed -i s/quay.io/gcr.io/ ./config/k8s/deployment.yaml
```

Commit and push the changes to watch OPA prevent the deployment.

## Giving Developers Feedback Sooner (Shift Left)

Wouldn't it be great if developers didn't have to wait for the entire CI/CD
pipeline to complete only to realize the operation they want to perform isn't
allowed? To give developers feedback sooner, we need to move the policy
prevention mechanisms earlier in the develoment lifecycle.

### Add Early Step to Pipeline

The following are two ways we can add an early step to the pipeline to shift
left.

#### Using Server Dry Run

One way to achieve this, is to add an initial step in the pipeline that
attempts to perform the `kubectl apply` operations with the `--server-dry-run`
flag so that we can get feedback sooner on whether the policy prevents this
operation. To do this, let's add a dry-run step to the pipeline prior to
anything else being run in the pipeline. Go ahead and apply these changes:

```bash
kubectl apply -f ./config/tekton/pipeline/pipeline-dryrun.yaml
```

Commit and push an empty commit to your development repo.

```bash
git commit -a -m "build commit" --allow-empty && git push origin mybranch
```

And watch the pipeline fail earlier from the `quay.io` to `gcr.io` change.

#### `conftest`

One way to achieve this, is to add an initial step in the pipeline that
executes `conftest` to perform the the policy evaluation to see if the policy
prevents this operation. To do this, let's add a `conftest` step to the
pipeline prior to anything else being run in the pipeline. Go ahead and apply
these changes:

```bash
kubectl apply -f ./config/tekton/task/conftest.yaml
kubectl apply -f ./config/tekton/pipeline/pipeline-conftest.yaml
```

Commit and push an empty commit to your development repo.

```bash
git commit -a -m "build commit" --allow-empty && git push origin mybranch
```

And watch the pipeline fail earlier from the `quay.io` to `gcr.io` change.

### Add Earlier Step to Development Workflow

We can give developers feedback even earlier in the developer lifecycle so that
the developer doesn't even have to kick off the CI/CD pipeline and consume
existing resources. In order to do that, we'll use a tool called
[`conftest`](https://github.com/instrumenta/conftest). It is a tool that
facilitates testing your configuration files against OPA. In our case, we want
to test the trusted registries Rego policy against our `deployment.yaml` file.

Using `conftest`, we can also leverage git `pre-commit` hooks to add a policy
check. In order to do that, create a symbolic link to the git `pre-commit` hook
script:

```bash
ln -rs hooks/pre-commit.sh .git/hooks/pre-commit
```

Now revert the previous `gcr.io` registry change and then attempt to use an
untrusted registry again:

```bash
sed -i s/quay.io/gcr.io/ ./config/k8s/deployment.yaml
```

Attempt to commit and you will receive the same error immediately instead of
waiting for the CI/CD pipeline to complete!

## Cleanup

Delete the namespaces:

```bash
kubectl delete namespace opa-example-app
kubectl delete namespace opa-example-app-trigger
```
