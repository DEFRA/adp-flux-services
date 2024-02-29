# ADP FluxCD Services
FluxCD repository for deploying ADP Platform business services. This is a secondary repository that will be referenced by GitRepositories from the main repository adp-flux-core.

## How it works - new and existing scaffolding
This repository is driven by a fully automated approach. Every time a new application is scaffolded or updated; the FluxCD Automated Bot will update this repository to either:
- Create a new business service and applications (check-in of manifests, YAML files, service configuration) or;
- Update an existing service core configuration with any updates and changes

Examples include new environment configuration, new services, patch updates, kustomizations, container image locations and versions etc.

## How it works - deployments
Every time a deployment happens, the automated FluxCD Bot will update the version image reference:

      OLD: version: "1.0.37" # {"$imagepolicy": "flux-config:service-xx-snd-03:tag"}
      NEW: version: "1.0.38" # {"$imagepolicy": "flux-config:service-xx-snd-03:tag"}

This means that the next version to be deployed will be v1.0.38 and Flux will reconcile within 5~ minutes.

**How does the Flux bot get triggered?** <br >
Every repository and every application follows the *sematic versioning* (semVer) strategy. This means that within the [package.json](https://github.com/DEFRA/ffc-demo-web/blob/d4e92b4c201b5770abfd7677e70e108a0530ad24/package.json#) file the version number gets updated on every new application release (merge into main). Once the merge into main is done, or a release into Sandbox environment from a Feature branch, the Flux CD Image Policy will trigger and update this repository. The deployment will then trigger.

