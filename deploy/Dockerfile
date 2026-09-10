FROM python:3.12-slim
# Exact versions captured from a working container (`docker exec wren pip freeze`).
# Upgrade path: edit wrenai pin in requirements.lock.txt, rebuild, verify, re-freeze.
COPY requirements.lock.txt /opt/wren/requirements.lock.txt
RUN pip install --no-cache-dir -r /opt/wren/requirements.lock.txt
COPY entrypoint.sh connection.yml /opt/wren/
RUN chmod +x /opt/wren/entrypoint.sh
WORKDIR /project
ENTRYPOINT ["/opt/wren/entrypoint.sh"]
