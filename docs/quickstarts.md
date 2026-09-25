# Quickstarts

*(cheat sheet for local dev commands, etc.)*

## mcp inspector

```bash
npx @modelcontextprotocol/inspector
```

add server ('http://localhost:3001/mcp/')

## container

build
```bash
podman build -t tidal-sonics-server .
```

run
```bash
podman run --rm --name tidal-sonics-dev tidal-sonics-server:latest
```

