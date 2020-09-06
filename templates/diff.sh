{% if k14_sops.found: %}
# Decrypt secrets and deploy
sops -d secrets/secrets.yaml | \
{% else: %}
# Deploy with secrets
{% endif %}
kapp deploy -a {{ k14.app }} \
{% if ytt.kapp.namespace is defined: %}
-n {{ ytt.kapp.namespace }} \
{% endif %}
--into-ns {{ k14_app_namespace }} \
-f manifest \
-c \
{%if k14_sops.found: %}
-f -
{% else: %}
-f secrets
{% endif %}
