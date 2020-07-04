K14
=========

This role simplifies the application of the [K14][k14] tools for generating kubernetes
configurations. Roles for specific software can use this role to handle the general work flow
configuring only the software specific portions. This role is never meant to be used
directly, only used by application roles to simply their creation.

Work flow
---------
The work flow supported by this charm is meant to generate site specific yaml files which
fully document each application as well as deployment scripts that can be used to apply the
files to a cluster. The general work flow is:
 * Download/Update Helm repository
 * Generate kubernetes objects from repository
 * Generate any additional supporting objects from application role
 * Apply user or application role overlay modifications to Helm files
 * Resolves image references to their digest form (immutable)
 * Write files to site/application specific folder for review and deployment

The process allows for multiple sites with site specific configuration as well as application
specific overlays if customization is needed on a per-site basis.

Directory Structure
-------------------
The final directory structure for a site and application will follow the following scheme:
```bash
sites/
└── site1
    ├── application
    │   ├── deploy.sh
    │   ├── diff.sh
    │   ├── manifest
    │   │   ├── ConfigMap.yaml
    │   │   ├── daemonset.yaml
    │   │   ├── deployment.yaml
    │   │   ├── namespace.yaml
    │   │   ├── rbac.yaml
    │   │   └── service-accounts.yaml
    │   ├── secrets
    │   │   └── secrets.yaml
    │   └── overlays
    │       └── manifest.yaml
    └── site.yaml
```
This role generates:
 * application folder
 * deploy and diff scripts
 * manifest folder populated with K8s objects
 * secrets folder with a secrets file (if used by the application role)

The site.yaml file is used for site specific settings and is not generated by this role.
The overlays folder and contents are not generated and are used to apply site specific
customizations to an application if they exist.

Inventory and Playbook
----------------------
The following variables must be configured in the Inventory for this role.
 * root_folder: Required for each host, specifies the site folder for a host
 * site_file: Required for each host, file path relative to root_folder for site.yaml file

An example inventory file deploying a single application to two sites is:
```bash
all:
    hosts:
        site1:
            root_folder: ./sites/site1
        site2:
            root_folder: ./sites/site2
    vars:
        ansible_connection: local
        ansible_python_interpreter: "{{ansible_playbook_python}}"
        site_file: site.yaml

application:
    hosts:
        site1:
        site2:

```

This example defines two sites. Each has a root_folder to generate the application files in.
The site_file is named site.yaml in the root of each site and is the same on all sites.

With the above inventory a playbook to generate deployment artefacts for both sites would be:
```bash
- hosts: application
  gather_facts: no
  roles:
      - application
```

With the above inventory and playbook, an application-role using this role to generate
deployment artifacts would be called with:
```bash
ansible-playbook -i inventory.yaml playbook.yaml
```

Running this playbook would apply the work flow and generate an application folder for each
site with the site specific settings ready for configuration management and deployment.

Requirements
------------
This role expects the following tools to be installed
 - ytt
 - kbld
 - helm3
 - git
 - sops (only if using encrypted secrets)
 - kapp (only used during deployment by the deployment scripts)

ytt and kapp  are part of the [k14s][k14] project. Overlays used by this role utilize ytt see
documentation from the ytt project for details.

Writing an Application Role
---------------------------
The following sections describe how to write a role for a specific application using this
role to perform most of the work flow.

Role Variables
--------------
Set the role variables in the defaults/main.yml file of your application role.

 * k14_app: The name of the application.
 * k14_helm_repo: The URL for the git repo
 * k14_helm_path: Path within the helm_repo to the chart

Main Task
---------
The application role should include this role in the tasks/main.yml

Ex:
```yaml
- name: Include k14
  include_role:
      name: k14
```

Variables
---------
Set helm values in the file `files/templates/helm-values.yaml`. These values will be used
when generating templates with helm. Site specific modifications can be made with overlays
described below.

When setting the helm-values ytt is used, values that should be exposed to the end user
should use ytt variables with defaults. The intention is not to wrap all helm settings but
some values, like namespaces, should be user customizable. This is done by creating the file
`files/templates/default-values.yaml` for your ytt data values. The values used here will be
overridden if specified in the site file.

Example values file:
```yaml
#@data/values
---
application:
    namespace: application
```

Example helm file:
```yaml
#@ load("@ytt:data", "data")
---
name: "helm-values"
namespace: #@data.values.application.namespace
```
The helm-values file needs to have the `name: "helm-values"` structure at the root, this
enables selecting this file for site specific overlays later.

Other objects
-------------
Any additional objects you need to configure the application should be defined in the
`files/templates` folder. Like `helm-values` ytt data can be used with `default-values` to
customize the templates. Custom objects created in this way are automatically copied into
the final manifest folder. 

Most likely you will want to create a namespace. Ex:
```yaml
#@ load("@ytt:data", "data")
---
apiVersion: v1
kind: Namespace
metadata:
  name: #@ data.values.application.namespace
```
Including the above in `files/templates/namespace.yaml` will render it into the final manifest.

Secrets
-------
If your application role needs to create secrets create the file
`files/secrets/secrets.yaml`. This file should contain all secrets to be generated, if
multiple documents are needed combine them into a single yaml file. This is required to
support automatic encrypting/decrypting via [sops][sops] without writing the values to disk.

Site Overrides
--------------
The above covers everything necessary to create an application role. Users of the role can make
site specific modifications using the sites.yaml file and a few overlay files. Ideally, the
most common configuration changes will be done via the sites file, with helm and manifest
overlays provided to allow full customization if necessary.

Site File
---------
The Site file allows for changing values defined in `default-values.yaml` for a given site.
This can be used to customize values that change between sites. This file should be used for
storing any secrets used in your role. This file supports detection of [sops][sops] and if
present will apply the sops to the secrets file and include a decryption step in the deploy
script.

The site file has one variable to configure how kapp deploys applications for the site. The
value of `kapp.namespaces`, if defined, will be included in the deploy.sh and diff.sh. This
configures where kapp stores the application deployment history.

Site example:
```yaml
kapp:
    namespace: kapp
application:
    namespace: custom-namespace
```
Helm Values Overlay
-------------------
An overlay can be applied to the helm-values even if the role doesn't expose the values for
modification in the site file. The overlay file should be defined in the application folder at 
`/overlays/helm.yaml`

If this file exists it will be used as an overlay to the settings built into this role.
Example:
```yaml
#@ load("@ytt:overlay", "overlay")

#@overlay/match by=overlay.subset({"name": "helm-values"})
---
#@overlay/match missing_ok=True
global:
    imageRegistry: myRegistryName
    imagePullSecrets:
        - myRegistryKeySecretName
```
The above overlay file will match on the helm-values document and add the imageRegistry options
which are available in the helm chart. This overlay file allows for site specific
modifications to the helm values as well as setting or change values that the application
role did not expose. Ideally, the role would be updated to allow modification for such
settings via the site file, but this provides a way to fully customize your configuration
even if the role is in the process of being updated.

Manifest Overlay
----------------
A final overlay can be applied against the manifest files. The overlay file should be defined
in the application folder at `/overlays/manifest.yaml` and will be applied as the last step.

Example:
```yaml
#@ load("@ytt:overlay", "overlay")

#@overlay/match by=overlay.subset({"kind": "DaemonSet"})
---
spec:
  template:
    spec:
      #@overlay/remove
      tolerations:
```
The above overlay will remove the tolerations from the DaemonSet. It is generally preferable
to use Helm Variables for configuration and reserve manifest overlays for items which are not
available via helm variables.

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).

[k14]:https://k14s.io/
[sops]:https://github.com/mozilla/sops