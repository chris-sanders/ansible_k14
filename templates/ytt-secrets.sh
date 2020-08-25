{% for item in k14_secrets_list["results"]: %}
    {% set secret = item.secrets_item %}
    echo "{{ site_file_content }}" | \
    ytt -f {{ secret.src }} \
    -f {{ ansible_parent_role_paths[1] }}/files/templates/{{ k14_default_values }} \
    -f - \
    --ignore-unknown-comments \
    {% if k14_sops.found: %}
	| sops --input-type yaml --output-type yaml -e /dev/stdin \
    {% endif %}
    > {{ app_folder.path }}/secrets/{{ secret.src.split('/')[-1] }}
{% endfor %}
