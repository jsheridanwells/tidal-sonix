# http/

One `.http` file per external service (`tidal.http`, `google.http`, `keyvault.http`), REST Client syntax. Saved real responses live in `responses/` with tokens redacted. Variables come from `http-client.env.json` (gitignored).

Rule: no C# client method exists for an endpoint until its request is here and a response is saved.
