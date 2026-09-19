class_name NetConfig
extends RefCounted

## Default server endpoint. `wrangler dev` serves this locally.
##
## The release workflow rewrites this line via sed when the SERVER_URL
## repository variable is set, so the deployed build points at the Worker.
## Keep it on one line, in this exact shape, or that substitution will miss.
const DEFAULT_SERVER_URL := "ws://127.0.0.1:8787/ws"

## Resolve the endpoint to connect to.
##
## In a browser, `?server=wss://host/ws` overrides the baked-in default, which
## makes it possible to point a deployed build at a local or staging server
## without rebuilding.
static func server_url() -> String:
	if OS.has_feature("web"):
		var override := _query_param("server")
		if override != "":
			return override
	return DEFAULT_SERVER_URL

static func _query_param(key: String) -> String:
	var search: String = str(JavaScriptBridge.eval("window.location.search", true))
	if search.is_empty() or search == "<null>":
		return ""
	for pair in search.trim_prefix("?").split("&", false):
		var bits := pair.split("=", true, 1)
		if bits.size() == 2 and bits[0] == key:
			return bits[1].uri_decode()
	return ""
