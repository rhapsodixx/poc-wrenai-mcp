FROM python:3.12-slim
RUN pip install --no-cache-dir "wrenai[postgres,mcp]" "mcp[cli]<2"  # wrenai 0.14 uses mcp 1.x FastMCP API
COPY entrypoint.sh connection.yml /opt/wren/
RUN chmod +x /opt/wren/entrypoint.sh
WORKDIR /project
ENTRYPOINT ["/opt/wren/entrypoint.sh"]
