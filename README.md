# ADP FluxCD Services
FluxCD repository for deploying ADP Platform business services. This is a secondary repository that will be referenced by GitRepositories from the main repository adp-flux-core.

## How it works - new and existing scaffolding
This repository is driven by a fully automated approach. Everytime a new application is scaffolded or updated, the FluxCD Automated Bot will update this repository to either:
- Create a new business service and applications (check-in of manifests, YAML files, service configuration) or;
- Update an existing service core configuration with any updates and changes

Examples include new environment configuration, new services, patch updates, kustomizations, container image locations and versions etc.

## How it works - deployments
Every time a deployment happens, the automated FluxCD Bot will update the version image reference:

      OLD: version: "1.0.37" # {"$imagepolicy": "flux-config:service-xx-snd-03:tag"}
      NEW: version: "1.0.38" # {"$imagepolicy": "flux-config:service-xx-snd-03:tag"}

This means that the nexr version to be deployed will be v1.0.38 and flux will reconcile within 5~ minutes.

