{% set filename = overlay_item.manifest_item.src.split('/')[-1] %}
ytt -f {{ overlay_item.manifest_item.src }} \
{% if manifest_overlay.stat.exists: %}
    -f {{ manifest_overlay.stat.path }} \
{% endif %}
{% if role_manifest_overlay.stat.exists: %}
    -f {{ role_manifest_overlay.stat.path }} \
{% endif %}
--ignore-unknown-comments \
| kbld -f- > {{ app_folder.path }}/manifest/{{ filename }}
